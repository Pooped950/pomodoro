import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/data/services/timer_service_protocol.dart';
import 'package:pomodoro/domain/timer/timer_engine.dart';
import 'package:pomodoro/domain/timer/timer_state.dart';

/// Dart ↔ 原生前台服务状态协议的单测。
/// key 一致性靠与 Kotlin KEY_* 常量的人工对照（见协议文件注释）。
void main() {
  final DateTime t0 = DateTime(2026, 1, 1, 9, 0, 0);
  const TimerConfig config = TimerConfig();

  group('toMap → fromMap round-trip', () {
    test('计时中状态还原（毫秒精度无损）', () {
      final TimerState s = TimerState.idle(
        phase: TimerPhase.focus,
        plannedSeconds: 1500,
      ).start(t0);

      final TimerState? back = TimerServiceProtocol.fromMap(
        TimerServiceProtocol.toMap(s, config),
      );

      expect(back, isNotNull);
      expect(back!.phase, TimerPhase.focus);
      expect(back.startedAt, s.startedAt);
      expect(back.plannedSeconds, 1500);
      expect(back.pausedAt, isNull);
      expect(back.completedPomodoros, 0);
      expect(back.isRunning, isTrue);
    });

    test('暂停中状态还原，pausedAt 保留且时间冻结语义不变', () {
      final TimerState s = TimerState.idle(
        phase: TimerPhase.focus,
        plannedSeconds: 60,
      ).start(t0).pause(t0.add(const Duration(seconds: 10)));

      final TimerState? back = TimerServiceProtocol.fromMap(
        TimerServiceProtocol.toMap(s, config),
      );

      expect(back!.isPaused, isTrue);
      expect(back.pausedAt, s.pausedAt);
      // 冻结在暂停点：5 小时后看仍然剩 50 秒
      expect(
        back.remainingSecondsAt(t0.add(const Duration(hours: 5))),
        50,
      );
    });
  });

  group('异常输入兜底', () {
    test('null / 空 map → null（原生无状态）', () {
      expect(TimerServiceProtocol.fromMap(null), isNull);
      expect(TimerServiceProtocol.fromMap(<Object?, Object?>{}), isNull);
    });

    test('未知 phase 回退到 focus，不抛异常', () {
      final TimerState? back = TimerServiceProtocol.fromMap(
        <Object?, Object?>{'phase': '??', 'startedAt': 123},
      );
      expect(back!.phase, TimerPhase.focus);
    });
  });

  test('countdownText 与主界面同格式（mm:ss 补零）', () {
    expect(TimerServiceProtocol.countdownText(0), '00:00');
    expect(TimerServiceProtocol.countdownText(9), '00:09');
    expect(TimerServiceProtocol.countdownText(65), '01:05');
    expect(TimerServiceProtocol.countdownText(1500), '25:00');
  });

  group('精确闹钟时刻 phaseEndMillis（M3 阶段三）', () {
    test('未开始 → null（不该排闹钟）', () {
      expect(
        TimerServiceProtocol.phaseEndMillis(
          TimerState.idle(phase: TimerPhase.focus, plannedSeconds: 1500),
        ),
        isNull,
      );
    });

    test('计时中 → startedAt + 计划时长', () {
      final TimerState s = TimerState.idle(
        phase: TimerPhase.focus,
        plannedSeconds: 1500,
      ).start(t0);

      expect(
        TimerServiceProtocol.phaseEndMillis(s),
        t0.add(const Duration(seconds: 1500)).millisecondsSinceEpoch,
      );
    });

    test('★ 暂停中 → null（闹钟必须撤掉，否则暂停期间会误响）', () {
      final TimerState s = TimerState.idle(
        phase: TimerPhase.focus,
        plannedSeconds: 1500,
      ).start(t0).pause(t0.add(const Duration(seconds: 60)));

      expect(TimerServiceProtocol.phaseEndMillis(s), isNull);
    });

    test('★ 累计暂停时长要算进结束时刻（暂停 5 分钟 → 结束时刻顺延 5 分钟）', () {
      final TimerState s = TimerState.idle(
        phase: TimerPhase.focus,
        plannedSeconds: 1500,
      )
          .start(t0)
          .pause(t0.add(const Duration(seconds: 300)))
          .resume(t0.add(const Duration(seconds: 600)));

      // 计划 1500s + 暂停 300s → 从 t0 起 1800s 后才到点
      expect(
        TimerServiceProtocol.phaseEndMillis(s),
        t0.add(const Duration(seconds: 1800)).millisecondsSinceEpoch,
      );
    });

    test('★ 与 remainingSecondsAt 自洽：到该时刻剩余恰为 0', () {
      final TimerState s = TimerState.idle(
        phase: TimerPhase.focus,
        plannedSeconds: 1500,
      )
          .start(t0)
          .pause(t0.add(const Duration(seconds: 300)))
          .resume(t0.add(const Duration(seconds: 600)));

      final DateTime atEnd = DateTime.fromMillisecondsSinceEpoch(
        TimerServiceProtocol.phaseEndMillis(s)!,
      );

      expect(s.remainingSecondsAt(atEnd), 0);
      expect(s.isExpiredAt(atEnd), isTrue);
      expect(
        s.remainingSecondsAt(atEnd.subtract(const Duration(seconds: 1))),
        1,
      );
    });

    test('★ 不自动开始时下一阶段是「待开始」——原生侧必须对齐', () {
      // 契约：Dart 侧 toPhase() 产出的下一阶段是"待开始"（startedAt = null）。
      // 原生 TimerForegroundService.advancePhase 在 autoStartNext=false 时
      // 必须把 startedAtMs 清零，否则状态会谎称"正在计时"（界面显示暂停按钮），
      // 而服务已停、闹钟已撤 —— 休息到点不会响。
      final TimerState afterFocus = TimerState.idle(
        phase: TimerPhase.focus,
        plannedSeconds: 1500,
      ).start(t0).copyWith(completedPomodoros: 1);

      final TimerState next = afterFocus.toPhase(TimerPhase.shortBreak, 300);

      expect(next.startedAt, isNull, reason: 'toPhase 语义是待开始，不应带 startedAt');
      expect(next.isIdle, isTrue);
      // 待开始状态下不该排闹钟
      expect(TimerServiceProtocol.phaseEndMillis(next), isNull);
      // 原生若回退成"把 startedAt 设成现在"，fromMap 就会把它误判成有状态
      expect(
        TimerServiceProtocol.fromMap(
          <Object?, Object?>{'phase': 'shortBreak', 'startedAt': 0},
        ),
        isNull,
        reason: 'startedAt 为 0 表示原生只是"待开始"，不该被当成有效计时状态',
      );
    });
  });
}