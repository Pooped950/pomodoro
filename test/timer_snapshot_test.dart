import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/timer/timer_engine.dart';
import 'package:pomodoro/domain/timer/timer_snapshot.dart';
import 'package:pomodoro/domain/timer/timer_state.dart';

/// 快照映射与恢复决策的单元测试 —— 方案文档 6.4 表 4 / 6.5②。
///
/// 恢复逻辑是纯函数，不依赖 SQLite，宿主机直接跑。
/// 持久层（sqflite）的正确性由真机/模拟器上的集成验证覆盖。
void main() {
  final DateTime t0 = DateTime(2026, 1, 1, 9, 0, 0);
  const TimerConfig config = TimerConfig();

  TimerState freshFocus({int seconds = 1500}) => TimerState.idle(
        phase: TimerPhase.focus,
        plannedSeconds: seconds,
      );

  group('行映射 round-trip', () {
    test('计时中的状态原样往返', () {
      final TimerState s = freshFocus().start(t0);
      final TimerState back = TimerSnapshotMapper.fromRow(
        TimerSnapshotMapper.toRow(s),
      );

      expect(back.phase, TimerPhase.focus);
      expect(back.startedAt, t0);
      expect(back.plannedSeconds, 1500);
      expect(back.pausedAt, isNull);
      expect(back.pausedTotal, Duration.zero);
      expect(back.completedPomodoros, 0);
      expect(back.isRunning, isTrue);
    });

    test('暂停中的状态原样往返（pausedAt / pausedTotal 保留）', () {
      final TimerState s = freshFocus(seconds: 60)
          .start(t0)
          .pause(t0.add(const Duration(seconds: 10)))
          .resume(t0.add(const Duration(seconds: 30)))
          .pause(t0.add(const Duration(seconds: 40)));
      final TimerState back = TimerSnapshotMapper.fromRow(
        TimerSnapshotMapper.toRow(s),
      );

      expect(back.isPaused, isTrue);
      expect(back.pausedAt, t0.add(const Duration(seconds: 40)));
      expect(back.pausedTotal, const Duration(seconds: 20));
    });

    test('未开始状态往返（startedAt 为 null，进度保留）', () {
      final TimerState s = TimerState.idle(
        phase: TimerPhase.shortBreak,
        plannedSeconds: 300,
        completedPomodoros: 2,
      );
      final TimerState back = TimerSnapshotMapper.fromRow(
        TimerSnapshotMapper.toRow(s),
      );

      expect(back.isIdle, isTrue);
      expect(back.phase, TimerPhase.shortBreak);
      expect(back.plannedSeconds, 300);
      expect(back.completedPomodoros, 2);
    });
  });

  group('恢复决策', () {
    test('无快照 → 全新专注待开始', () {
      final SnapshotRecovery r = recoverFromSnapshot(
        row: null,
        now: t0,
        config: config,
      );

      expect(r.hadSnapshot, isFalse);
      expect(r.state.isIdle, isTrue);
      expect(r.state.phase, TimerPhase.focus);
      expect(r.state.plannedSeconds, 1500);
    });

    test('快照未开始 → 原样恢复（保留进度）', () {
      final Map<String, Object?> row = TimerSnapshotMapper.toRow(
        TimerState.idle(
          phase: TimerPhase.focus,
          plannedSeconds: 1500,
          completedPomodoros: 3,
        ),
      );

      final SnapshotRecovery r = recoverFromSnapshot(
        row: row,
        now: t0.add(const Duration(hours: 5)),
        config: config,
      );

      expect(r.hadSnapshot, isTrue);
      expect(r.state.isIdle, isTrue);
      expect(r.state.completedPomodoros, 3);
    });

    test('★ 计时中未走完 → 原样恢复，剩余时间由绝对时间戳接算', () {
      final Map<String, Object?> row = TimerSnapshotMapper.toRow(
        freshFocus().start(t0),
      );
      final DateTime now = t0.add(const Duration(minutes: 10));

      final SnapshotRecovery r = recoverFromSnapshot(
        row: row,
        now: now,
        config: config,
      );

      expect(r.expiredDuringAbsence, isFalse);
      expect(r.state.isRunning, isTrue);
      // 恢复发生在"离开" 10 分钟后：剩余必须按真实时间算出 15 分钟
      expect(r.state.remainingSecondsAt(now), 900);
    });

    test('★ 离开期间专注已走完 → 计入 1 个番茄，流转短休息待开始', () {
      final Map<String, Object?> row = TimerSnapshotMapper.toRow(
        freshFocus().start(t0),
      );
      final DateTime now = t0.add(const Duration(minutes: 30));

      final SnapshotRecovery r = recoverFromSnapshot(
        row: row,
        now: now,
        config: config,
      );

      expect(r.expiredDuringAbsence, isTrue);
      expect(r.state.isIdle, isTrue);
      expect(r.state.phase, TimerPhase.shortBreak);
      expect(r.state.completedPomodoros, 1);
      expect(r.state.plannedSeconds, 300);
    });

    test('★ 离开期间休息已走完 → 回到专注，不计入番茄', () {
      final Map<String, Object?> row = TimerSnapshotMapper.toRow(
        TimerState.idle(
          phase: TimerPhase.shortBreak,
          plannedSeconds: 300,
          completedPomodoros: 1,
        ).start(t0),
      );
      final DateTime now = t0.add(const Duration(minutes: 10));

      final SnapshotRecovery r = recoverFromSnapshot(
        row: row,
        now: now,
        config: config,
      );

      expect(r.expiredDuringAbsence, isTrue);
      expect(r.state.phase, TimerPhase.focus);
      expect(r.state.completedPomodoros, 1);
      expect(r.state.plannedSeconds, 1500);
    });

    test('暂停中的快照 → 原样恢复，搁置多久都不会过期', () {
      final Map<String, Object?> row = TimerSnapshotMapper.toRow(
        freshFocus(seconds: 60).start(t0).pause(t0.add(const Duration(seconds: 10))),
      );
      final DateTime now = t0.add(const Duration(hours: 5));

      final SnapshotRecovery r = recoverFromSnapshot(
        row: row,
        now: now,
        config: config,
      );

      expect(r.expiredDuringAbsence, isFalse);
      expect(r.state.isPaused, isTrue);
      // 时间冻结在暂停点：剩 50 秒
      expect(r.state.remainingSecondsAt(now), 50);
    });
  });
}
