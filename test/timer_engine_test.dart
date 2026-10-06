import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/utils/formatters.dart';
import 'package:pomodoro/domain/timer/timer_engine.dart';
import 'package:pomodoro/domain/timer/timer_state.dart';

/// 计时引擎单元测试
///
/// ★ 这组测试是整个项目的安全网 ★
///
/// 方案文档 6.5① 指出：计时必须用绝对时间戳，不能用定时器递减。
/// 这组用例把"锁屏 / 暂停 / 进程重启"这些真实场景固定下来，
/// 以后任何人（或 AI）改动计时逻辑，跑一遍就知道有没有破坏核心行为。
///
/// 运行：flutter test
void main() {
  // 固定一个基准时刻，避免测试依赖真实时间
  final DateTime t0 = DateTime(2026, 1, 1, 9, 0, 0);

  TimerState freshFocus({int seconds = 1500}) => TimerState.idle(
        phase: TimerPhase.focus,
        plannedSeconds: seconds,
      );

  group('剩余时间计算', () {
    test('未开始时剩余时间等于计划时长', () {
      final TimerState s = freshFocus();
      expect(s.isIdle, isTrue);
      expect(s.remainingSecondsAt(t0), 1500);
      expect(s.progressAt(t0), 0);
      expect(s.remainingFractionAt(t0), 1);
    });

    test('开始 10 秒后剩余时间减少 10 秒', () {
      final TimerState s = freshFocus().start(t0);
      expect(s.isRunning, isTrue);
      expect(s.remainingSecondsAt(t0.add(const Duration(seconds: 10))), 1490);
    });

    test('★ 锁屏 5 分钟：剩余时间正确减少 5 分钟', () {
      // 真实场景：用户点开始后立刻锁屏，系统冻结了 Dart 定时器。
      // 因为用的是绝对时间戳，这里直接"跳"到 5 分钟后，结果必须准确。
      final TimerState s = freshFocus().start(t0);
      expect(s.remainingSecondsAt(t0.add(const Duration(minutes: 5))), 1200);
    });

    test('★ 锁屏 25 分钟：到点后剩余时间为 0，不会变成负数', () {
      final TimerState s = freshFocus().start(t0);
      final DateTime after = t0.add(const Duration(minutes: 40));
      expect(s.remainingSecondsAt(after), 0);
      expect(s.isExpiredAt(after), isTrue);
      expect(s.progressAt(after), 1.0);
      expect(s.remainingFractionAt(after), 0.0);
    });

    test('进度随时间线性增长', () {
      final TimerState s = freshFocus(seconds: 100).start(t0);
      expect(s.progressAt(t0.add(const Duration(seconds: 25))), closeTo(0.25, 0.001));
      expect(s.progressAt(t0.add(const Duration(seconds: 50))), closeTo(0.50, 0.001));
    });
  });

  group('暂停 / 继续', () {
    test('暂停后时间不再流逝（暂停 2 小时也一样）', () {
      final TimerState s = freshFocus()
          .start(t0)
          .pause(t0.add(const Duration(minutes: 3)));

      expect(s.isPaused, isTrue);
      expect(s.isRunning, isFalse);

      // 暂停期间过了 2 小时，已流逝时间应该仍然停在 3 分钟
      // （1500 - 180 = 1320）
      expect(s.remainingSecondsAt(t0.add(const Duration(hours: 2))), 1320);
    });

    test('继续后从暂停点接着走，不补算暂停时长', () {
      final TimerState paused = freshFocus()
          .start(t0)
          .pause(t0.add(const Duration(minutes: 3)));

      final DateTime resumeAt = t0.add(const Duration(hours: 2));
      final TimerState resumed = paused.resume(resumeAt);

      expect(resumed.isRunning, isTrue);

      // 刚继续：已流逝仍停在 3 分钟，剩 1500 - 180 = 1320 秒
      expect(resumed.remainingSecondsAt(resumeAt), 1320);

      // 继续 1 分钟：剩 1260 秒
      expect(
        resumed.remainingSecondsAt(resumeAt.add(const Duration(minutes: 1))),
        1260,
      );
    });

    test('反复暂停继续，累计暂停时长正确', () {
      TimerState s = freshFocus().start(t0);

      // 暂停 10 秒
      s = s.pause(t0.add(const Duration(seconds: 10)));
      s = s.resume(t0.add(const Duration(seconds: 20)));

      // 暂停 30 秒
      s = s.pause(t0.add(const Duration(seconds: 50)));
      s = s.resume(t0.add(const Duration(seconds: 80)));

      // 总共过了 80 秒，其中暂停 40 秒 -> 实际计时 40 秒
      expect(s.remainingSecondsAt(t0.add(const Duration(seconds: 80))), 1460);
    });

    test('暂停状态下不会触发到点', () {
      final TimerState s = freshFocus(seconds: 60)
          .start(t0)
          .pause(t0.add(const Duration(seconds: 10)));

      expect(s.isExpiredAt(t0.add(const Duration(hours: 5))), isFalse);
    });
  });

  group('进程重启后恢复', () {
    test('★ 从持久化字段重建状态，剩余时间依然准确', () {
      // 模拟：App 被杀掉，只留下 timer_snapshot 里的这几个字段
      final TimerState restored = TimerState(
        phase: TimerPhase.focus,
        plannedSeconds: 1500,
        startedAt: t0,
      );

      expect(restored.isRunning, isTrue);
      expect(
        restored.remainingSecondsAt(t0.add(const Duration(minutes: 10))),
        900,
      );
    });

    test('带暂停记录的恢复', () {
      final TimerState restored = TimerState(
        phase: TimerPhase.focus,
        plannedSeconds: 1500,
        startedAt: t0,
        pausedTotal: const Duration(minutes: 2),
        pausedAt: t0.add(const Duration(minutes: 5)),
      );

      // 从开始到暂停点 5 分钟，其中暂停 2 分钟 -> 实际计时 3 分钟
      expect(
        restored.remainingSecondsAt(t0.add(const Duration(hours: 1))),
        1500 - 180,
      );
    });
  });

  group('阶段流转规则', () {
    const TimerConfig config = TimerConfig(longBreakInterval: 4);

    test('专注结束进入短休息', () {
      expect(
        TimerEngine.nextPhase(
          current: TimerPhase.focus,
          completedPomodorosAfter: 1,
          config: config,
        ),
        TimerPhase.shortBreak,
      );
    });

    test('第 4 个专注结束进入长休息', () {
      expect(
        TimerEngine.nextPhase(
          current: TimerPhase.focus,
          completedPomodorosAfter: 4,
          config: config,
        ),
        TimerPhase.longBreak,
      );
    });

    test('第 8 个专注结束也进入长休息', () {
      expect(
        TimerEngine.nextPhase(
          current: TimerPhase.focus,
          completedPomodorosAfter: 8,
          config: config,
        ),
        TimerPhase.longBreak,
      );
    });

    test('休息结束回到专注', () {
      expect(
        TimerEngine.nextPhase(
          current: TimerPhase.shortBreak,
          completedPomodorosAfter: 1,
          config: config,
        ),
        TimerPhase.focus,
      );
      expect(
        TimerEngine.nextPhase(
          current: TimerPhase.longBreak,
          completedPomodorosAfter: 4,
          config: config,
        ),
        TimerPhase.focus,
      );
    });

    test('只有专注阶段增加计数', () {
      expect(TimerEngine.completedAfter(TimerPhase.focus, 2), 3);
      expect(TimerEngine.completedAfter(TimerPhase.shortBreak, 2), 2);
      expect(TimerEngine.completedAfter(TimerPhase.longBreak, 4), 4);
    });

    test('间隔配置异常时不会除以零', () {
      const TimerConfig bad = TimerConfig(longBreakInterval: 0);
      expect(
        TimerEngine.nextPhase(
          current: TimerPhase.focus,
          completedPomodorosAfter: 1,
          config: bad,
        ),
        TimerPhase.longBreak,
      );
    });
  });

  group('配置映射到秒数', () {
    test('三种阶段取到各自的时长', () {
      const TimerConfig config = TimerConfig(
        focusMinutes: 25,
        shortBreakMinutes: 5,
        longBreakMinutes: 15,
      );
      expect(config.secondsFor(TimerPhase.focus), 1500);
      expect(config.secondsFor(TimerPhase.shortBreak), 300);
      expect(config.secondsFor(TimerPhase.longBreak), 900);
    });
  });

  group('时长格式化', () {
    test('mm:ss 补零', () {
      expect(formatClock(0), '00:00');
      expect(formatClock(9), '00:09');
      expect(formatClock(65), '01:05');
      expect(formatClock(1500), '25:00');
    });

    test('负数按 0 处理', () {
      expect(formatClock(-5), '00:00');
    });

    test('超过一小时正常进位', () {
      expect(formatClock(3600), '60:00');
    });

    test('人类可读时长', () {
      expect(formatDurationHuman(30), '30s');
      expect(formatDurationHuman(300), '5m');
      expect(formatDurationHuman(8100), '2h 15m');
      expect(formatDurationHuman(7200), '2h');
    });
  });
}
