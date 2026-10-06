import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/stats/stats_summary.dart';
import 'package:pomodoro/domain/task/task.dart';
import 'package:pomodoro/domain/timer/session_record.dart';
import 'package:pomodoro/domain/timer/timer_state.dart';

/// 统计聚合的单测（M5-③）。全部是纯函数，不连数据库。
///
/// 这里守的核心是**口径**：
///   - 归属日期一律按 `startedAt`，与主界面「今日 N/8」保持一致
///   - 「专注时长」含未走完的专注，但「完成番茄数」只数走完的
///   - 柱状图必须每天一根柱子，没数据的那天补 0（否则横轴会错位）
void main() {
  final DateTime day1 = DateTime(2026, 10, 5); // 周一
  final DateTime day2 = DateTime(2026, 10, 6);

  SessionRecord focus({
    required DateTime at,
    int actual = 1500,
    bool completed = true,
    int? taskId,
  }) =>
      SessionRecord(
        phase: TimerPhase.focus,
        plannedSeconds: 1500,
        actualSeconds: actual,
        startedAt: at,
        isCompleted: completed,
        taskId: taskId,
      );

  SessionRecord rest({
    required DateTime at,
    int actual = 300,
    TimerPhase phase = TimerPhase.shortBreak,
  }) =>
      SessionRecord(
        phase: phase,
        plannedSeconds: 300,
        actualSeconds: actual,
        startedAt: at,
        isCompleted: true,
      );

  Task task(int id, String title) => Task(
        id: id,
        title: title,
        createdAt: day1,
      );

  group('summarizeDay', () {
    test('空列表 → 全 0，且 isEmpty 为 true', () {
      final DayOverview o = summarizeDay(<SessionRecord>[], day1);
      expect(o, DayOverview.empty);
      expect(o.isEmpty, isTrue);
      expect(o.averageFocusSeconds, 0, reason: '不能除零');
      expect(o.completionRate, 0, reason: '不能除零');
    });

    test('只统计当天，别的日子的记录不算进来', () {
      final DayOverview o = summarizeDay(
        <SessionRecord>[
          focus(at: day1.add(const Duration(hours: 9))),
          focus(at: day2.add(const Duration(hours: 9))),
        ],
        day1,
      );
      expect(o.completedPomodoros, 1);
    });

    test('★ 专注时长含未走完的，完成番茄数只数走完的', () {
      final DayOverview o = summarizeDay(
        <SessionRecord>[
          focus(at: day1.add(const Duration(hours: 9))), // 走完
          focus(
            at: day1.add(const Duration(hours: 10)),
            actual: 300,
            completed: false, // 跳过
          ),
        ],
        day1,
      );

      expect(o.focusSeconds, 1800, reason: '1500 + 300，跳过的那次也花了时间');
      expect(o.completedPomodoros, 1, reason: '只有走完的才算番茄');
      expect(o.focusSessionCount, 2);
      expect(o.abandonedCount, 1);
      expect(o.averageFocusSeconds, 900);
      expect(o.completionRate, 0.5);
    });

    test('休息时长把短休息和长休息都算进去，但不计入专注', () {
      final DayOverview o = summarizeDay(
        <SessionRecord>[
          focus(at: day1.add(const Duration(hours: 9))),
          rest(at: day1.add(const Duration(hours: 9, minutes: 25))),
          rest(
            at: day1.add(const Duration(hours: 10)),
            actual: 900,
            phase: TimerPhase.longBreak,
          ),
        ],
        day1,
      );

      expect(o.breakSeconds, 1200, reason: '300 + 900');
      expect(o.focusSeconds, 1500);
      expect(o.completedPomodoros, 1, reason: '休息不算番茄');
    });

    test('★ 跨午夜的番茄归属"开始那天"（不劈成两半）', () {
      final SessionRecord r = focus(
        at: DateTime(2026, 10, 5, 23, 50),
        actual: 1500,
      );

      final DayOverview before = summarizeDay(<SessionRecord>[r], day1);
      final DayOverview after = summarizeDay(<SessionRecord>[r], day2);

      expect(before.completedPomodoros, 1);
      expect(after.completedPomodoros, 0, reason: '一个番茄只能属于一天');
    });
  });

  group('dailyFocusSeries', () {
    test('★ 每天一根柱子，没数据的那天补 0（否则横轴会错位）', () {
      final List<DailyFocus> s = dailyFocusSeries(
        <SessionRecord>[focus(at: day1.add(const Duration(hours: 9)))],
        endDay: day1,
        days: 7,
      );

      expect(s.length, 7);
      expect(s.last.day, DateTime(2026, 10, 5));
      expect(s.first.day, DateTime(2026, 9, 29), reason: '今天往前数 6 天');
      expect(s.last.focusSeconds, 1500);
      expect(s.first.focusSeconds, 0);
      expect(s.first.hasData, isFalse);
    });

    test('升序排列：最后一根是 endDay', () {
      final List<DailyFocus> s = dailyFocusSeries(
        <SessionRecord>[],
        endDay: day1,
        days: 3,
      );
      expect(
        s.map((DailyFocus d) => d.day).toList(),
        <DateTime>[
          DateTime(2026, 10, 3),
          DateTime(2026, 10, 4),
          DateTime(2026, 10, 5),
        ],
      );
    });

    test('同一天多条记录会被合并', () {
      final List<DailyFocus> s = dailyFocusSeries(
        <SessionRecord>[
          focus(at: day1.add(const Duration(hours: 9))),
          focus(at: day1.add(const Duration(hours: 11)), actual: 600),
        ],
        endDay: day1,
        days: 1,
      );

      expect(s.single.focusSeconds, 2100);
      expect(s.single.completedPomodoros, 2);
    });

    test('休息记录不进柱状图（柱状图画的是专注）', () {
      final List<DailyFocus> s = dailyFocusSeries(
        <SessionRecord>[rest(at: day1.add(const Duration(hours: 9)))],
        endDay: day1,
        days: 1,
      );
      expect(s.single.focusSeconds, 0);
    });

    test('窗口外的记录被忽略', () {
      final List<DailyFocus> s = dailyFocusSeries(
        <SessionRecord>[focus(at: DateTime(2026, 9, 1))],
        endDay: day1,
        days: 7,
      );
      expect(maxFocusSeconds(s), 0);
    });

    test('days < 1 时按 1 天处理，不返回空列表', () {
      expect(
        dailyFocusSeries(<SessionRecord>[], endDay: day1, days: 0).length,
        1,
      );
    });
  });

  group('taskDistribution', () {
    test('按时长降序排列', () {
      final List<TaskSlice> d = taskDistribution(
        <SessionRecord>[
          focus(at: day1.add(const Duration(hours: 9)), actual: 300, taskId: 1),
          focus(at: day1.add(const Duration(hours: 10)), actual: 900, taskId: 2),
        ],
        tasks: <Task>[task(1, '写方案'), task(2, '看论文')],
      );

      expect(d.map((TaskSlice s) => s.label).toList(), <String>['看论文', '写方案']);
      expect(d.first.focusSeconds, 900);
    });

    test('taskId 翻译成任务标题', () {
      final List<TaskSlice> d = taskDistribution(
        <SessionRecord>[
          focus(at: day1.add(const Duration(hours: 9)), taskId: 7),
        ],
        tasks: <Task>[task(7, '复习高数')],
      );
      expect(d.single.label, '复习高数');
      expect(d.single.taskId, 7);
    });

    test('★ 未绑定任务的归一类，不丢', () {
      final List<TaskSlice> d = taskDistribution(
        <SessionRecord>[
          focus(at: day1.add(const Duration(hours: 9)), actual: 600),
        ],
        tasks: <Task>[],
      );
      expect(d.single.taskId, isNull);
      expect(d.single.label, '未绑定任务');
      expect(d.single.focusSeconds, 600);
    });

    test('★ 任务已被删除时单独归一类，而不是丢掉（否则用户觉得统计少了一截）', () {
      final List<TaskSlice> d = taskDistribution(
        <SessionRecord>[
          focus(at: day1.add(const Duration(hours: 9)), taskId: 99),
        ],
        tasks: <Task>[task(1, '还在的任务')],
      );
      expect(d.single.label, '已删除的任务');
      expect(d.single.taskId, 99);
    });

    test('休息记录不进任务分布', () {
      expect(
        taskDistribution(
          <SessionRecord>[rest(at: day1.add(const Duration(hours: 9)))],
          tasks: <Task>[],
        ),
        isEmpty,
      );
    });

    test('★ limit 把长尾合并成「其他」，且总量不丢', () {
      final List<SessionRecord> all = <SessionRecord>[
        for (int i = 1; i <= 4; i++)
          focus(
            at: day1.add(Duration(hours: i)),
            actual: 100 * (5 - i), // 400 / 300 / 200 / 100
            taskId: i,
          ),
      ];

      final List<TaskSlice> d = taskDistribution(
        all,
        tasks: <Task>[for (int i = 1; i <= 4; i++) task(i, '任务$i')],
        limit: 2,
      );

      expect(d.length, 3, reason: '2 个 + 「其他」');
      expect(d.last.label, '其他');
      expect(d.last.focusSeconds, 300, reason: '200 + 100，一条都不能丢');

      int sum = 0;
      for (final TaskSlice s in d) {
        sum += s.focusSeconds;
      }
      expect(sum, 1000, reason: '合并前后总量必须一致');
    });

    test('时长相同的项按名字排，保证顺序稳定（刷新不会跳来跳去）', () {
      final List<TaskSlice> d = taskDistribution(
        <SessionRecord>[
          focus(at: day1.add(const Duration(hours: 9)), actual: 300, taskId: 1),
          focus(at: day1.add(const Duration(hours: 10)), actual: 300, taskId: 2),
        ],
        tasks: <Task>[task(1, 'B 任务'), task(2, 'A 任务')],
      );
      expect(d.map((TaskSlice s) => s.label).toList(), <String>['A 任务', 'B 任务']);
    });
  });

  group('maxFocusSeconds', () {
    test('返回最大单日专注秒数；空列表返回 0', () {
      expect(maxFocusSeconds(<DailyFocus>[]), 0);
      expect(
        maxFocusSeconds(<DailyFocus>[
          DailyFocus(day: day1, focusSeconds: 0, completedPomodoros: 0),
          DailyFocus(day: day2, focusSeconds: 0, completedPomodoros: 0),
        ]),
        0,
      );
      expect(
        maxFocusSeconds(<DailyFocus>[
          DailyFocus(day: day1, focusSeconds: 600, completedPomodoros: 1),
          DailyFocus(day: day2, focusSeconds: 1800, completedPomodoros: 2),
        ]),
        1800,
      );
    });
  });

  group('日期标签', () {
    test('weekdayShort 周一~周日正确', () {
      // 2026-10-05 是周一
      expect(weekdayShort(DateTime(2026, 10, 5)), '周一');
      expect(weekdayShort(DateTime(2026, 10, 6)), '周二');
      expect(weekdayShort(DateTime(2026, 10, 11)), '周日');
    });

    test('monthDayLabel 形如 10/5', () {
      expect(monthDayLabel(DateTime(2026, 10, 5)), '10/5');
    });

    test('dayTitle 今天 / 具体日期', () {
      expect(dayTitle(DateTime(2026, 10, 5, 20), DateTime(2026, 10, 5, 1)), '今天');
      expect(dayTitle(DateTime(2026, 10, 4), DateTime(2026, 10, 5)), '10月4日');
    });

    test('isSameDay 只比年月日', () {
      expect(
        isSameDay(DateTime(2026, 10, 5, 0, 1), DateTime(2026, 10, 5, 23, 59)),
        isTrue,
      );
      expect(
        isSameDay(DateTime(2026, 10, 5), DateTime(2026, 10, 6)),
        isFalse,
      );
    });
  });
}
