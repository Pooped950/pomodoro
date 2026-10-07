import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/timetable/course.dart';
import 'package:pomodoro/domain/timetable/course_override.dart';

/// 「本周实际显示什么」的计算 —— 三点点菜单的数据层。
///
/// 纯函数，把"临时删除下周自动回来""临时加课只在本周出现"这两条
/// 用户确认过的规则钉死。
void main() {
  final DateTime monday = DateTime(2026, 10, 5); // 2026-10-05 是周一
  final DateTime wednesday = DateTime(2026, 10, 7); // 同一周的周三

  Course course({
    int id = 1,
    int weekday = 1,
    int start = 1,
    int end = 2,
    String name = '甲课',
  }) =>
      Course(
        id: id,
        weekday: weekday,
        startPeriod: start,
        endPeriod: end,
        name: name,
        createdAt: DateTime(2026, 10, 1),
      );

  CourseOverride hide({
    int weekday = 1,
    int start = 1,
    int end = 2,
    DateTime? monday,
  }) =>
      CourseOverride(
        id: 11,
        kind: CourseOverrideKind.hide,
        weekday: weekday,
        startPeriod: start,
        endPeriod: end,
        weekMonday: monday,
        createdAt: DateTime(2026, 10, 7),
      );

  group('mondayOf', () {
    test('★ 周中的日子归到同一周的周一', () {
      // 2026-10-07 是周三
      expect(mondayOf(wednesday), DateTime(2026, 10, 5));
    });

    test('周一当天就是自己；周日归到六天前', () {
      expect(mondayOf(monday), monday);
      expect(mondayOf(DateTime(2026, 10, 11)), monday); // 10-11 是周日
    });

    test('跨月/跨年也归对', () {
      // 2026-11-01 是周日，那一周的周一在 10 月
      expect(mondayOf(DateTime(2026, 11, 1)), DateTime(2026, 10, 26));
    });
  });

  group('effectiveCoursesForWeek', () {
    test('★ 本周隐藏：格子消失', () {
      final List<Course> out = effectiveCoursesForWeek(
        courses: <Course>[course()],
        overrides: <CourseOverride>[hide(monday: monday)],
        weekMonday: monday,
      );
      expect(out, isEmpty);
    });

    test('★ 隐藏只对那一周生效：下周自动回来', () {
      final List<Course> out = effectiveCoursesForWeek(
        courses: <Course>[course()],
        overrides: <CourseOverride>[hide(monday: monday)],
        weekMonday: monday.add(const Duration(days: 7)),
      );
      expect(out.length, 1, reason: '下周不是那一周了，隐藏失效');
    });

    test('隐藏按格子匹配：同周其他课不受影响', () {
      final List<Course> out = effectiveCoursesForWeek(
        courses: <Course>[
          course(weekday: 1, start: 1, end: 2, name: '甲课'),
          course(id: 2, weekday: 2, start: 3, end: 4, name: '乙课'),
        ],
        overrides: <CourseOverride>[hide(monday: monday)],
        weekMonday: monday,
      );
      expect(out.map((Course c) => c.name), <String>['乙课']);
    });

    test('★ 本周加课：合成一节临时课，id 为负（不与真课撞）', () {
      final List<Course> out = effectiveCoursesForWeek(
        courses: <Course>[course()],
        overrides: <CourseOverride>[
          CourseOverride(
            id: 7,
            kind: CourseOverrideKind.add,
            weekday: 3,
            startPeriod: 5,
            endPeriod: 6,
            weekMonday: monday,
            name: '临时讲座',
            location: '报告厅',
            createdAt: DateTime(2026, 10, 7),
          ),
        ],
        weekMonday: monday,
      );
      expect(out.length, 2);
      expect(out.last.id, -7, reason: '负 id = 临时课，永远不与 courses 自增 id 撞');
      expect(out.last.name, '临时讲座');
      expect(out.last.location, '报告厅');
      expect(out.last.periodSpan, 2);
    });

    test('加课也只在那一周出现', () {
      final List<Course> out = effectiveCoursesForWeek(
        courses: <Course>[],
        overrides: <CourseOverride>[
          CourseOverride(
            id: 7,
            kind: CourseOverrideKind.add,
            weekday: 3,
            startPeriod: 5,
            endPeriod: 5,
            weekMonday: monday,
            name: '临时讲座',
            createdAt: DateTime(2026, 10, 7),
          ),
        ],
        weekMonday: wednesday.add(const Duration(days: 7)),
      );
      expect(out, isEmpty);
    });

    test('retime 本轮不应用（改时间的 UI 还没做），有数据也不崩', () {
      final List<Course> out = effectiveCoursesForWeek(
        courses: <Course>[course()],
        overrides: <CourseOverride>[
          CourseOverride(
            id: 9,
            kind: CourseOverrideKind.retime,
            weekday: 1,
            startPeriod: 1,
            endPeriod: 2,
            weekMonday: monday,
            startMinute: 480,
            endMinute: 530,
            createdAt: DateTime(2026, 10, 7),
          ),
        ],
        weekMonday: monday,
      );
      expect(out.length, 1);
    });

    test('weekMonday 为 null 的例外是"永久"语义，hide/add 不当它用', () {
      // hide/add 建出来都应该带 weekMonday；这个测试钉住"漏填时宁可
      // 不生效也别乱生效"的取舍 —— null 不是任何一周，全周都不命中
      final List<Course> out = effectiveCoursesForWeek(
        courses: <Course>[course()],
        overrides: <CourseOverride>[hide(monday: null)],
        weekMonday: monday,
      );
      expect(out.length, 1);
    });
  });
}
