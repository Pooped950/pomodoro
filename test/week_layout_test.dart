import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/timetable/course.dart';
import 'package:pomodoro/domain/timetable/period_time.dart';
import 'package:pomodoro/domain/timetable/week_layout.dart';

/// 周视图**版面计算**的回归测试。
///
/// 「画哪几列 / 画哪几行 / 午休切在哪」这三件事决定了整张网格的形状，
/// 算错一处整页都会歪，所以必须钉死。
void main() {
  group('周视图要画哪几列', () {
    test('周一到周五有课 → 5 列', () {
      expect(
        weekViewColumns(_coursesOn(<int>[1, 2, 3, 4, 5])),
        <int>[1, 2, 3, 4, 5],
      );
    });

    test('★ 周六有课就自动多一列，不用改代码', () {
      expect(
        weekViewColumns(_coursesOn(<int>[1, 5, 6])),
        <int>[1, 2, 3, 4, 5, 6],
      );
    });

    test('★ 只有周三有课 → 也排到周三，周二不会凭空消失', () {
      expect(weekViewColumns(_coursesOn(<int>[3])), <int>[1, 2, 3]);
    });

    test('一节课都没有时退回周一~周五，空网格也有个合理形状', () {
      expect(weekViewColumns(const <Course>[]), <int>[1, 2, 3, 4, 5]);
    });
  });

  group('网格要画多少行', () {
    final TimetableSchedule eight = buildSchedule(_anchors);

    test('节次表 8 节、课都在范围内 → 8 行', () {
      expect(
        weekViewPeriodCount(eight, _coursesOn(<int>[1, 2])),
        8,
      );
    });

    test('★ 课排到第 9 节但节次表只排了 8 节 → 补到 9 行，课不能被裁掉', () {
      final Course c = _course(weekday: 1, start: 9, end: 9);
      expect(weekViewPeriodCount(eight, <Course>[c]), 9);
    });

    test('节次表是空的（时间没排出来）→ 按课的最大节次兜底', () {
      const TimetableSchedule none = TimetableSchedule();
      expect(
        weekViewPeriodCount(none, <Course>[_course(weekday: 1, start: 3, end: 4)]),
        4,
      );
    });

    test('完全没课也没节次表 → 0 行（页面会走空白态，不画网格）', () {
      expect(
        weekViewPeriodCount(const TimetableSchedule(), const <Course>[]),
        0,
      );
    });
  });

  group('午休切在哪两节之间', () {
    test('★ 典型课表：上午 4 节 + 午休 + 下午 4 节 → 切在第 4 节之后', () {
      final TimetableSchedule s = buildSchedule(_anchors);
      expect(s.periods.length, 8);
      expect(lunchBreakAfterPeriod(s.periods), 4);
    });

    test('★ 课间均匀的课表**不切** —— 随手一刀会把下午的课误判成上午', () {
      final List<PeriodTime> uniform = <PeriodTime>[
        for (int i = 0; i < 6; i++)
          PeriodTime(
            period: i + 1,
            startMinute: 480 + i * 58,
            endMinute: 480 + i * 58 + 45,
          ),
      ];
      expect(lunchBreakAfterPeriod(uniform), isNull);
    });

    test('★ 节次首尾相接（没有课间）时，只有午休一个大空档也能认出来', () {
      final List<PeriodTime> packed = <PeriodTime>[
        const PeriodTime(period: 1, startMinute: 480, endMinute: 525),
        const PeriodTime(period: 2, startMinute: 525, endMinute: 570),
        const PeriodTime(period: 3, startMinute: 570, endMinute: 615),
        // 午休 225 分钟
        const PeriodTime(period: 4, startMinute: 840, endMinute: 885),
        const PeriodTime(period: 5, startMinute: 885, endMinute: 930),
      ];
      expect(lunchBreakAfterPeriod(packed), 3);
    });

    test('10 分钟大课间不算午休（有绝对下限兜着）', () {
      final List<PeriodTime> bigBreak = <PeriodTime>[
        const PeriodTime(period: 1, startMinute: 480, endMinute: 525),
        const PeriodTime(period: 2, startMinute: 535, endMinute: 580),
        const PeriodTime(period: 3, startMinute: 590, endMinute: 635),
        const PeriodTime(period: 4, startMinute: 645, endMinute: 690),
      ];
      expect(lunchBreakAfterPeriod(bigBreak), isNull);
    });

    test('节数太少谈不上分段', () {
      expect(lunchBreakAfterPeriod(const <PeriodTime>[]), isNull);
      expect(
        lunchBreakAfterPeriod(<PeriodTime>[
          const PeriodTime(period: 1, startMinute: 480, endMinute: 525),
          const PeriodTime(period: 2, startMinute: 840, endMinute: 885),
        ]),
        isNull,
      );
    });
  });
}

// ---------------------------------------------------------------------------
// 夹具
// ---------------------------------------------------------------------------

/// 一份典型中学课表的锚点：上午 4 节 8:00~11:40，下午 4 节 14:00~17:30
const ScheduleAnchors _anchors = ScheduleAnchors(
  firstStartMinute: 8 * 60,
  morningEndMinute: 11 * 60 + 40,
  afternoonStartMinute: 14 * 60,
  lastEndMinute: 17 * 60 + 30,
  periodMinutes: 45,
  morningPeriodCount: 4,
  afternoonPeriodCount: 4,
);

List<Course> _coursesOn(List<int> weekdays) => <Course>[
      for (final int d in weekdays) _course(weekday: d, start: 1, end: 1),
    ];

Course _course({required int weekday, required int start, required int end}) =>
    Course(
      id: 0,
      weekday: weekday,
      startPeriod: start,
      endPeriod: end,
      name: '课',
      createdAt: DateTime(2026, 10, 7),
    );
