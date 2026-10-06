import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/timer/session_record.dart';
import 'package:pomodoro/domain/timer/timer_snapshot.dart';
import 'package:pomodoro/domain/timer/timer_state.dart';

/// M5-② 任务绑定的单测。
///
/// 核心语义：绑定在 `start()` 时**捕获**，阶段流转时**清空**，
/// 暂停/继续**保留**，并且快照与 session 记录都要带上它。
void main() {
  final DateTime t0 = DateTime(2026, 10, 5, 9, 0, 0);

  TimerState idle() => TimerState.idle(
        phase: TimerPhase.focus,
        plannedSeconds: 1500,
      );

  group('TimerState 的任务绑定', () {
    test('start 时带上 taskId', () {
      expect(idle().start(t0, taskId: 7).taskId, 7);
    });

    test('不传 taskId 时为 null', () {
      expect(idle().start(t0).taskId, isNull);
    });

    test('★ 阶段流转清空绑定（新阶段要重新绑）', () {
      final TimerState s = idle().start(t0, taskId: 7);
      expect(s.toPhase(TimerPhase.shortBreak, 300).taskId, isNull);
    });

    test('★ 暂停 / 继续保留绑定', () {
      final TimerState s = idle().start(t0, taskId: 7);
      final TimerState paused = s.pause(t0.add(const Duration(seconds: 10)));
      expect(paused.taskId, 7);
      expect(paused.resume(t0.add(const Duration(seconds: 20))).taskId, 7);
    });

    test('clearTaskId 能显式清掉', () {
      expect(idle().start(t0, taskId: 7).copyWith(clearTaskId: true).taskId,
          isNull);
    });

    test('★ start(taskId: null) 是清掉而不是保留上一次的绑定', () {
      final TimerState bound = idle().start(t0, taskId: 7);
      expect(bound.start(t0, taskId: null).taskId, isNull);
    });
  });

  group('快照带上 taskId', () {
    test('round-trip 保留绑定', () {
      final TimerState s = idle().start(t0, taskId: 42);
      final TimerState back =
          TimerSnapshotMapper.fromRow(TimerSnapshotMapper.toRow(s));
      expect(back.taskId, 42);
    });

    test('未绑定时存 null', () {
      expect(TimerSnapshotMapper.toRow(idle().start(t0))['task_id'], isNull);
    });
  });

  group('session 记录带上 taskId', () {
    test('绑定了任务时记录里带上', () {
      final TimerState s = idle().start(t0, taskId: 9);
      final SessionRecord? r = sessionForReplacedState(
        previous: s,
        endedAt: t0.add(const Duration(seconds: 1500)),
        completed: true,
        taskId: s.taskId,
      );

      expect(r!.taskId, 9);
      expect(r.countsAsPomodoro, isTrue);
    });

    test('未绑定时为 null', () {
      final TimerState s = idle().start(t0);
      final SessionRecord? r = sessionForReplacedState(
        previous: s,
        endedAt: t0.add(const Duration(seconds: 1500)),
        completed: true,
        taskId: s.taskId,
      );

      expect(r!.taskId, isNull);
    });
  });
}
