import 'package:meta/meta.dart';

/// 计时阶段。
enum TimerPhase {
  /// 专注
  focus,

  /// 短休息
  shortBreak,

  /// 长休息
  longBreak;

  /// 界面显示用的中文名
  String get label => switch (this) {
        TimerPhase.focus => '专注中',
        TimerPhase.shortBreak => '短休息',
        TimerPhase.longBreak => '长休息',
      };

  /// 未开始时的提示语
  String get idleLabel => switch (this) {
        TimerPhase.focus => '准备专注',
        TimerPhase.shortBreak => '准备休息',
        TimerPhase.longBreak => '准备长休息',
      };

  bool get isBreak => this != TimerPhase.focus;
}

/// 计时状态（不可变）。
///
/// ★★★ 核心设计（方案文档 6.5①）★★★
///
/// 这里**不保存"剩余多少秒"**，而是保存「开始时刻 + 计划时长 + 累计暂停时长」
/// 这三个静态值。剩余时间永远由 `remainingSecondsAt(now)` 实时算出。
///
/// 为什么必须这样做：
///   Android 在息屏 / 应用进入后台时会节流甚至完全暂停 Dart 定时器。
///   如果按"每秒减一"来实现，锁屏 25 分钟回来可能只走了 2 分钟。
///   而用绝对时间戳，无论定时器被冻结多久，算出来的时间永远准确。
///
/// 所以：任何地方都不要再引入"计时器递减"的写法。
@immutable
class TimerState {
  const TimerState({
    required this.phase,
    required this.plannedSeconds,
    this.startedAt,
    this.pausedTotal = Duration.zero,
    this.pausedAt,
    this.completedPomodoros = 0,
    this.taskId,
  });

  /// 未开始 / 已重置的状态
  factory TimerState.idle({
    required TimerPhase phase,
    required int plannedSeconds,
    int completedPomodoros = 0,
  }) =>
      TimerState(
        phase: phase,
        plannedSeconds: plannedSeconds,
        completedPomodoros: completedPomodoros,
      );

  /// 当前阶段
  final TimerPhase phase;

  /// 本阶段计划时长（秒）
  final int plannedSeconds;

  /// 本阶段开始的绝对时刻。null 表示尚未开始。
  final DateTime? startedAt;

  /// 之前累计的暂停时长（不含当前这一次暂停）
  final Duration pausedTotal;

  /// 当前暂停的时刻。null 表示未暂停。
  final DateTime? pausedAt;

  /// 已完成（走满）的专注个数，用于长休息判定与今日进度
  final int completedPomodoros;

  /// 本次专注绑定的任务 id（M5）。
  ///
  /// **在 [start] 时捕获**，而不是每次读"当前选中的任务"——
  /// 否则用户专注到一半去任务页换了选中项，这次专注就会被记到新任务头上。
  /// 休息阶段与流转后的新阶段都为 null（绑定不跟着走）。
  final int? taskId;

  bool get isIdle => startedAt == null;

  bool get isPaused => startedAt != null && pausedAt != null;

  bool get isRunning => startedAt != null && pausedAt == null;

  bool get isStarted => startedAt != null;

  /// 已实际流逝的时长。
  ///
  /// 暂停期间不累加：用 `pausedAt ?? now` 作为"计时终点"，
  /// 这样暂停后即使过了一小时，elapsed 也不会增长。
  Duration elapsedAt(DateTime now) {
    final DateTime? start = startedAt;
    if (start == null) return Duration.zero;
    final DateTime end = pausedAt ?? now;
    final Duration raw = end.difference(start) - pausedTotal;
    return raw.isNegative ? Duration.zero : raw;
  }

  /// 剩余秒数，永不为负。
  int remainingSecondsAt(DateTime now) {
    final int remaining = plannedSeconds - elapsedAt(now).inSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  /// 已完成的进度，0.0 ~ 1.0
  double progressAt(DateTime now) {
    if (plannedSeconds <= 0) return 1;
    final double p = elapsedAt(now).inMilliseconds / (plannedSeconds * 1000);
    return p.clamp(0.0, 1.0);
  }

  /// 剩余比例，0.0 ~ 1.0。环形进度条画这个值（时间越少圈越短）。
  double remainingFractionAt(DateTime now) => 1 - progressAt(now);

  /// 本阶段是否已经走完
  bool isExpiredAt(DateTime now) => remainingSecondsAt(now) <= 0;

  // ---------------------------------------------------------------------
  // 状态迁移：全部返回新实例，不做原地修改
  // ---------------------------------------------------------------------

  /// 开始计时（从未开始状态）。
  ///
  /// [taskId] 是这次专注要绑定的任务 —— **在这里捕获**，
  /// 之后用户去任务页换了选中项也不会影响本次专注的归属。
  TimerState start(DateTime now, {int? taskId}) => copyWith(
        startedAt: now,
        taskId: taskId,
        clearTaskId: taskId == null,
      );

  /// 暂停
  TimerState pause(DateTime now) {
    if (!isRunning) return this;
    return copyWith(pausedAt: now);
  }

  /// 继续
  TimerState resume(DateTime now) {
    final DateTime? paused = pausedAt;
    if (paused == null) return this;
    return copyWith(
      pausedAt: null,
      clearPausedAt: true,
      pausedTotal: pausedTotal + now.difference(paused),
    );
  }

  /// 切换到下一个阶段（保留已完成番茄数）。
  ///
  /// 注意**不保留 taskId** —— 新阶段是一次新的计时，绑定要重新来。
  /// （用户选中的任务在别处单独存，界面上下次开始会自动带上。）
  TimerState toPhase(TimerPhase next, int seconds) => TimerState(
        phase: next,
        plannedSeconds: seconds,
        completedPomodoros: completedPomodoros,
      );

  TimerState copyWith({
    TimerPhase? phase,
    int? plannedSeconds,
    DateTime? startedAt,
    Duration? pausedTotal,
    DateTime? pausedAt,
    bool clearStartedAt = false,
    bool clearPausedAt = false,
    int? completedPomodoros,
    int? taskId,
    bool clearTaskId = false,
  }) =>
      TimerState(
        phase: phase ?? this.phase,
        plannedSeconds: plannedSeconds ?? this.plannedSeconds,
        startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
        pausedTotal: pausedTotal ?? this.pausedTotal,
        pausedAt: clearPausedAt ? null : (pausedAt ?? this.pausedAt),
        completedPomodoros: completedPomodoros ?? this.completedPomodoros,
        taskId: clearTaskId ? null : (taskId ?? this.taskId),
      );

  @override
  String toString() => 'TimerState(phase: $phase, planned: $plannedSeconds, '
      'startedAt: $startedAt, pausedTotal: $pausedTotal, pausedAt: $pausedAt, '
      'completed: $completedPomodoros, taskId: $taskId)';
}
