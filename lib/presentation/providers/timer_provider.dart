import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/session_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../data/repositories/timer_snapshot_repository.dart';
import '../../data/services/foreground_service.dart';
import '../../data/services/timer_service_protocol.dart';
import '../../domain/settings/reminder_settings.dart';
import '../../domain/timer/session_record.dart';
import '../../domain/timer/timer_engine.dart';
import '../../domain/timer/timer_snapshot.dart';
import '../../domain/timer/timer_state.dart';
import 'app_settings_provider.dart';
import 'stats_provider.dart';
import 'task_provider.dart';

/// 时钟源：每秒发一次当前时间。
///
/// 注意：它**只负责触发界面重绘**，不是计时的事实来源。
/// 事实来源是 [TimerState] 里的绝对时间戳（方案文档 6.5①）。
/// 即使这个流被系统冻结，剩余时间算出来依然正确。
final clockProvider = StreamProvider<DateTime>((ref) => _tick());

Stream<DateTime> _tick() async* {
  // 先立即发一次，避免界面首帧没有时间可用
  yield DateTime.now();
  yield* Stream<DateTime>.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now(),
  );
}

/// 用户配置（时长、长休息间隔等）—— M4 起持久化到 `settings` 表。
///
/// 启动时异步读库（读完前先给默认值，不阻塞首帧）；
/// 之后每次改动都落库，实现"改了设置重启还在"。
class TimerConfigNotifier extends Notifier<TimerConfig> {
  @override
  TimerConfig build() {
    unawaited(_restore());
    return const TimerConfig();
  }

  Future<void> _restore() async {
    try {
      final TimerConfig? saved =
          await ref.read(settingsRepositoryProvider).readTimerConfig();
      if (saved == null) return;
      // 用户在读取完成前已经改过设置了 → 别用库里的旧值覆盖他的操作
      if (state != const TimerConfig()) return;
      state = saved;
    } catch (_) {
      // 仓库未注入（测试环境）/ 读取失败 → 用默认值，不阻塞启动
    }
  }

  void update(TimerConfig Function(TimerConfig current) transform) =>
      _set(transform(state));

  void setFocusMinutes(int minutes) =>
      _set(state.copyWith(focusMinutes: minutes));

  void setShortBreakMinutes(int minutes) =>
      _set(state.copyWith(shortBreakMinutes: minutes));

  void setLongBreakMinutes(int minutes) =>
      _set(state.copyWith(longBreakMinutes: minutes));

  void setLongBreakInterval(int interval) =>
      _set(state.copyWith(longBreakInterval: interval));

  void setAutoStartNext(bool value) =>
      _set(state.copyWith(autoStartNext: value));

  /// 统一出口：更新内存态 + 落库。未注入仓库（纯逻辑测试）时静默跳过。
  void _set(TimerConfig next) {
    state = next;
    unawaited(_persist(next));
  }

  Future<void> _persist(TimerConfig config) async {
    try {
      await ref.read(settingsRepositoryProvider).writeTimerConfig(config);
    } on UnimplementedError {
      // provider 未注入（纯逻辑测试环境）
    } catch (_) {
      // 落盘失败不拖垮设置页
    }
  }
}

final configProvider = NotifierProvider<TimerConfigNotifier, TimerConfig>(
  TimerConfigNotifier.new,
);

/// 计时器状态与操作
class TimerNotifier extends Notifier<TimerState> {
  @override
  TimerState build() {
    // 监听时钟：只用来判断"是否到点"，不做递减
    ref.listen<AsyncValue<DateTime>>(clockProvider, (_, AsyncValue<DateTime> next) {
      final DateTime? now = next.value;
      if (now != null) _onTick(now);
    });

    final TimerConfig config = ref.read(configProvider);

    // 设置页改了时长时，未开始的计时立即跟随变化。
    // 计时中不改 —— 否则一个 25 分钟的专注跑到一半会突然变成 30 分钟。
    ref.listen<TimerConfig>(configProvider, (_, TimerConfig next) {
      final TimerState s = state;
      if (!s.isIdle) return;
      _commit(TimerState.idle(
        phase: s.phase,
        plannedSeconds: next.secondsFor(s.phase),
        completedPomodoros: s.completedPomodoros,
      ));
    });

    // 通知栏按钮（暂停/继续/跳过）由原生服务推给 Dart，这里统一应用
    ForegroundService.setActionHandler(_applyServiceAction);

    // 提醒开关变化时也要重推给原生服务 —— 服务需要它来决定到点用哪个通知渠道。
    // 只影响"响不响"，不影响闹钟排程（静默时到点依然出通知）。
    ref.listen<ReminderSettings>(reminderSettingsProvider,
        (_, ReminderSettings next) {
      unawaited(_syncNative(state));
    });

    final TimerState baseline = TimerState.idle(
      phase: TimerPhase.focus,
      plannedSeconds: config.secondsFor(TimerPhase.focus),
    );

    // 启动恢复（方案 6.5② 第三层"回前台补偿"的冷启动部分）：
    // 异步读快照，读出来之前界面先显示基线，不阻塞首帧。
    unawaited(_restoreFromDisk(baseline));

    return baseline;
  }

  /// 从磁盘快照恢复计时状态。
  /// 若用户在恢复完成前已经动手操作（状态对象不再是基线），放弃覆盖。
  Future<void> _restoreFromDisk(TimerState baseline) async {
    try {
      final Map<String, Object?>? row =
          await ref.read(timerSnapshotRepositoryProvider).load();
      final SnapshotRecovery recovery = recoverFromSnapshot(
        row: row,
        now: DateTime.now(),
        config: ref.read(configProvider),
      );
      if (!recovery.hadSnapshot) return;
      if (state != baseline) return;

      // 离开期间这次专注已经走完 → **补一条 session 记录**。
      //
      // 不补的话，"息屏 / 关掉 App 期间完成的番茄"永远不会进统计 ——
      // 而 recovery.state 已经是下一阶段了，原始信息只能从快照行还原。
      if (recovery.expiredDuringAbsence) {
        final TimerState? expired =
            row == null ? null : TimerSnapshotMapper.fromRow(row);
        if (expired != null && expired.isStarted) {
          final DateTime endedAt = expired.startedAt!.add(
            Duration(
              seconds: expired.plannedSeconds + expired.pausedTotal.inSeconds,
            ),
          );
          _recordSession(expired, endedAt, completed: true);
        }
      }

      _commit(recovery.state);
    } catch (_) {
      // 快照损坏 / 读取失败都不应阻塞 App 启动
    }
  }

  /// 把一次「即将被替换掉的计时」落成 session 记录（M4，方案 6.4 表 2）。
  ///
  /// 三条路径都会走到这里：自然到点 / 跳过或放弃 / 原生服务在后台推进了阶段。
  /// 未注入仓库（纯逻辑测试环境）时静默跳过；落盘失败不拖垮计时。
  void _recordSession(
    TimerState previous,
    DateTime endedAt, {
    required bool completed,
  }) {
    final SessionRecord? record = sessionForReplacedState(
      previous: previous,
      endedAt: endedAt,
      completed: completed,
      // 任务绑定在 start() 时就捕获进 TimerState，这里直接取
      taskId: previous.taskId,
    );
    if (record == null) return;

    try {
      final SessionRepository repo = ref.read(sessionRepositoryProvider);
      unawaited(() async {
        try {
          await repo.insert(record);
          // 绑定了任务、且这是一个**完整走完的专注** → 给任务的番茄数 +1。
          // 跳过/放弃不计入（countsAsPomodoro 已经把这些排除掉了）。
          final int? taskId = record.taskId;
          if (record.countsAsPomodoro && taskId != null) {
            await ref.read(taskRepositoryProvider).incrementCompleted(taskId);
            await ref.read(taskListProvider.notifier).refresh();
          }
          // 主界面「今日 N / 8」跟着刷新
          ref.invalidate(todayFocusCountProvider);
          // 统计页的数据源也跟着失效 —— 不然刚跑完一个番茄切到统计页，
          // 看到的还是上一次的快照（页面被 PageView 保活，不会自己重建）
          ref.invalidate(statsProvider);
        } catch (_) {
          // 落盘失败不拖垮计时
        }
      }());
    } on UnimplementedError {
      // provider 未注入（纯逻辑测试环境）
    } catch (_) {
      // 同上
    }
  }

  /// 统一的状态提交口：更新内存态 + 同步落盘快照（方案 6.4 表 4）。
  /// Riverpod 3 没有 listenSelf，所有变更必须走这里，保证条条路径都持久化。
  /// 测试环境未注入仓库时静默跳过，磁盘失败也不阻塞计时。
  void _commit(TimerState next) {
    state = next;
    try {
      unawaited(ref.read(timerSnapshotRepositoryProvider).save(next));
    } on UnimplementedError {
      // provider 未注入（纯逻辑测试环境）
    } catch (_) {
      // 落盘失败不拖垮计时
    }
    // 前台服务跟随（方案 6.5② 第一层）：运行/暂停 → 启动或更新；未开始 → 撤通知
    unawaited(_syncNative(next));
  }

  /// 把状态推给原生前台服务（Kotlin 侧自持同样的绝对时间戳状态）
  Future<void> _syncNative(TimerState s) async {
    try {
      final ForegroundService service = ref.read(foregroundServiceProvider);
      if (s.isRunning || s.isPaused) {
        await service.startOrUpdate(
          TimerServiceProtocol.toMap(
            s,
            ref.read(configProvider),
            reminder: ref.read(reminderSettingsProvider),
          ),
        );
      } else {
        await service.stop();
      }
    } catch (_) {
      // 原生层不可用（测试环境 / 服务起不来）→ 走 M3 止损线：仅 App 内提醒
    }
  }

  /// 应用来自通知栏按钮的动作（原生服务推送，见 ForegroundService.setActionHandler）
  void _applyServiceAction(String action) {
    final DateTime now = DateTime.now();
    switch (action) {
      case 'pause':
        if (state.isRunning) _commit(state.pause(now));
      case 'resume':
        if (state.isPaused) _commit(state.resume(now));
      case 'skip':
        if (!state.isIdle) _advance(now, countFocus: false);
    }
  }

  /// 回前台时拉取原生侧最新状态。
  /// 用户可能在通知栏按了暂停/继续/跳过（方案 6.5⑥），服务在后台期间
  /// 是计时权威，Dart 与它不一致时以服务为准。
  Future<void> syncFromNative() async {
    try {
      final Map<Object?, Object?>? map =
          await ref.read(foregroundServiceProvider).getState();
      final TimerState? native = TimerServiceProtocol.fromMap(map);
      if (native == null) return;
      if (_sameTimerState(native, state)) return;

      final TimerState previous = state;
      final DateTime endedAt = native.startedAt ?? DateTime.now();

      // 原生协议不带任务绑定，所以这里要自己决定保留还是清掉：
      //   - 只是暂停 / 继续 → **保留**绑定（否则从通知栏暂停一下就丢了归属）
      //   - 阶段推进了      → **清掉**，与 TimerState.toPhase() 的语义一致
      final bool phaseAdvanced = native.phase != previous.phase ||
          native.startedAt?.millisecondsSinceEpoch !=
              previous.startedAt?.millisecondsSinceEpoch;

      // M4：原生服务在后台把阶段推进了 —— Dart 的 _onTick 没机会触发，
      // 这里补一条"被替换掉"的记录。用新阶段的开始时刻当结束时刻，
      // 并以它判断上一阶段是否真的走完（唯一索引保证不会重复写入）。
      _recordSession(previous, endedAt, completed: previous.isExpiredAt(endedAt));

      _commit(
        phaseAdvanced ? native : native.copyWith(taskId: previous.taskId),
      );
    } catch (_) {
      // 通道不可用（测试环境）
    }
  }

  /// 时间按毫秒比较：原生通道只有毫秒精度，直接 == 会因微秒位误判"不同"
  static bool _sameTimerState(TimerState a, TimerState b) =>
      a.phase == b.phase &&
      a.startedAt?.millisecondsSinceEpoch ==
          b.startedAt?.millisecondsSinceEpoch &&
      a.plannedSeconds == b.plannedSeconds &&
      a.pausedAt?.millisecondsSinceEpoch == b.pausedAt?.millisecondsSinceEpoch &&
      a.pausedTotal.inSeconds == b.pausedTotal.inSeconds &&
      a.completedPomodoros == b.completedPomodoros;

  /// 开始 / 暂停 / 继续，三态合一，供主按钮调用
  void toggle() {
    final DateTime now = DateTime.now();
    final TimerState s = state;

    if (s.isIdle) {
      // 开始专注时把「当前选中的任务」绑进去（M5-②）。
      // 在这里捕获而不是每帧读，是为了让"专注到一半换任务"不影响本次归属。
      _commit(s.start(now, taskId: ref.read(selectedTaskIdProvider)));
    } else if (s.isRunning) {
      _commit(s.pause(now));
    } else {
      _commit(s.resume(now));
    }
  }

  /// 跳过当前阶段（不计入专注数）
  void skip() => _advance(DateTime.now(), countFocus: false);

  /// 放弃本次专注，回到未开始状态（不计入专注数）
  void abandon() {
    final TimerConfig config = ref.read(configProvider);
    // M4：放弃也算一条记录，只是 is_completed = false
    _recordSession(state, DateTime.now(), completed: false);
    _commit(TimerState.idle(
      phase: TimerPhase.focus,
      plannedSeconds: config.secondsFor(TimerPhase.focus),
      completedPomodoros: state.completedPomodoros,
    ));
  }

  /// 每分钟的定时回调：只做一件事——检查是否到点
  void _onTick(DateTime now) {
    final TimerState s = state;
    if (!s.isRunning) return;
    if (!s.isExpiredAt(now)) return;
    _advance(now, countFocus: true);
  }

  void _advance(DateTime now, {required bool countFocus}) {
    final TimerConfig config = ref.read(configProvider);
    final TimerState s = state;

    // M4：这一阶段到此结束，先落一条 session 记录。
    // countFocus 为 true 表示"自然走完"（_onTick 触发），false 表示被跳过。
    _recordSession(s, now, completed: countFocus);

    final int completed = countFocus
        ? TimerEngine.completedAfter(s.phase, s.completedPomodoros)
        : s.completedPomodoros;

    final TimerPhase next = TimerEngine.nextPhase(
      current: s.phase,
      completedPomodorosAfter: completed,
      config: config,
    );

    final TimerState nextState = TimerState.idle(
      phase: next,
      plannedSeconds: config.secondsFor(next),
      completedPomodoros: completed,
    );

    _commit(config.autoStartNext ? nextState.start(now) : nextState);
  }
}

final timerProvider = NotifierProvider<TimerNotifier, TimerState>(
  TimerNotifier.new,
);

/// 界面用的"当前时刻"。
/// 时钟还没发出第一帧时回退到 DateTime.now()，避免首帧空白。
final nowProvider = Provider<DateTime>((ref) {
  return ref.watch(clockProvider).value ?? DateTime.now();
});

/// 主界面「今日 N / 8」的数据源 —— 从 sessions 实时聚合（M4）。
///
/// 之前用的是 `TimerState.completedPomodoros`：那是内存里的**轮次计数**，
/// 语义是"本轮已完成几个"（用于判定长休息），重启就归零，
/// 也不等于"今天完成了几个"。改成查库后语义才正确。
final todayFocusCountProvider = FutureProvider<int>((Ref ref) async {
  try {
    return await ref
        .watch(sessionRepositoryProvider)
        .completedFocusCountOn(DateTime.now());
  } catch (_) {
    // 仓库未注入（测试环境）/ 查询失败 → 0，界面照常渲染
    return 0;
  }
});
