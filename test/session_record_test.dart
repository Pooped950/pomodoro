import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/timer/session_record.dart';
import 'package:pomodoro/domain/timer/timer_state.dart';

/// sessions 记录的单测（M4）。全部是纯函数，不需要数据库。
void main() {
  final DateTime t0 = DateTime(2026, 10, 5, 9, 0, 0);

  TimerState focus({int seconds = 1500}) =>
      TimerState.idle(phase: TimerPhase.focus, plannedSeconds: seconds)
          .start(t0);

  group('sessionForReplacedState', () {
    test('未开始 → null（不该产生记录）', () {
      expect(
        sessionForReplacedState(
          previous:
              TimerState.idle(phase: TimerPhase.focus, plannedSeconds: 1500),
          endedAt: t0,
          completed: true,
        ),
        isNull,
      );
    });

    test('专注自然走完 → actualSeconds 等于计划时长', () {
      final SessionRecord? r = sessionForReplacedState(
        previous: focus(),
        endedAt: t0.add(const Duration(seconds: 1500)),
        completed: true,
      );

      expect(r, isNotNull);
      expect(r!.phase, TimerPhase.focus);
      expect(r.plannedSeconds, 1500);
      expect(r.actualSeconds, 1500);
      expect(r.startedAt, t0);
      expect(r.endedAt, t0.add(const Duration(seconds: 1500)));
      expect(r.isCompleted, isTrue);
      expect(r.countsAsPomodoro, isTrue);
    });

    test('★ App 被冻结导致超时 → actualSeconds 封顶到计划时长', () {
      final SessionRecord? r = sessionForReplacedState(
        previous: focus(),
        endedAt: t0.add(const Duration(minutes: 40)),
        completed: true,
      );

      expect(
        r!.actualSeconds,
        1500,
        reason: '不封顶会写出"25 分钟的番茄实际跑了 40 分钟"',
      );
    });

    test('★ 暂停期间不计入实际时长', () {
      // 跑了 300s → 暂停 600s → 继续跑满剩下的 1200s
      final TimerState s = focus()
          .pause(t0.add(const Duration(seconds: 300)))
          .resume(t0.add(const Duration(seconds: 900)));

      final SessionRecord? r = sessionForReplacedState(
        previous: s,
        endedAt: t0.add(const Duration(seconds: 2100)),
        completed: true,
      );

      expect(r!.actualSeconds, 1500, reason: '实际跑满 1500s，暂停的 600s 不算');
    });

    test('跳过 → is_completed=false，不计入番茄', () {
      final SessionRecord? r = sessionForReplacedState(
        previous: focus(),
        endedAt: t0.add(const Duration(seconds: 600)),
        completed: false,
      );

      expect(r!.isCompleted, isFalse);
      expect(r.actualSeconds, 600);
      expect(r.countsAsPomodoro, isFalse);
    });

    test('休息阶段走完 → is_completed=true，但不算番茄', () {
      final TimerState s =
          TimerState.idle(phase: TimerPhase.shortBreak, plannedSeconds: 300)
              .start(t0);

      final SessionRecord? r = sessionForReplacedState(
        previous: s,
        endedAt: t0.add(const Duration(seconds: 300)),
        completed: true,
      );

      expect(r!.isCompleted, isTrue);
      expect(r.countsAsPomodoro, isFalse, reason: '只有专注阶段计入番茄');
    });
  });

  group('SessionMapper 行映射', () {
    test('round-trip 无损（含 endedAt / taskId）', () {
      final SessionRecord r = SessionRecord(
        phase: TimerPhase.focus,
        plannedSeconds: 1500,
        actualSeconds: 1499,
        startedAt: t0,
        endedAt: t0.add(const Duration(seconds: 1499)),
        isCompleted: true,
        taskId: 7,
      );

      final SessionRecord back = SessionMapper.fromRow(SessionMapper.toRow(r));

      expect(back.phase, r.phase);
      expect(back.plannedSeconds, r.plannedSeconds);
      expect(back.actualSeconds, r.actualSeconds);
      expect(back.startedAt, r.startedAt);
      expect(back.endedAt, r.endedAt);
      expect(back.isCompleted, isTrue);
      expect(back.taskId, 7);
    });

    test('未绑定任务 / 未结束 → null 字段正确往返', () {
      final SessionRecord r = SessionRecord(
        phase: TimerPhase.shortBreak,
        plannedSeconds: 300,
        actualSeconds: 120,
        startedAt: t0,
        isCompleted: false,
      );

      final Map<String, Object?> row = SessionMapper.toRow(r);
      expect(row['task_id'], isNull);
      expect(row['ended_at'], isNull);
      expect(row['is_completed'], 0);

      final SessionRecord back = SessionMapper.fromRow(row);
      expect(back.taskId, isNull);
      expect(back.endedAt, isNull);
      expect(back.isCompleted, isFalse);
    });
  });

  group('dayRange', () {
    test('左闭右开，跨日边界正确', () {
      final ({DateTime from, DateTime to}) r =
          dayRange(DateTime(2026, 10, 5, 23, 59, 59));

      expect(r.from, DateTime(2026, 10, 5));
      expect(r.to, DateTime(2026, 10, 6));
    });

    test('★ ISO-8601 字符串的字典序即时间序（按天范围查询依赖这一点）', () {
      final ({DateTime from, DateTime to}) r = dayRange(DateTime(2026, 10, 5));
      final String from = r.from.toIso8601String();
      final String to = r.to.toIso8601String();
      final String inside = DateTime(2026, 10, 5, 12, 30).toIso8601String();
      final String before = DateTime(2026, 10, 4, 23, 59).toIso8601String();

      expect(inside.compareTo(from) >= 0 && inside.compareTo(to) < 0, isTrue);
      expect(before.compareTo(from) < 0, isTrue);
    });
  });
}
