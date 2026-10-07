import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/timetable/course.dart';
import 'package:pomodoro/domain/timetable/period_time.dart';
import 'package:pomodoro/presentation/pages/timetable/week_grid_view.dart';

/// 周视图网格的**组件测试**。
///
/// ## 为什么要用组件测试钉住，而不是只靠代码审查
///
/// 这张网格全靠绝对定位（`Positioned` 的 `top/height` 都是算出来的）。
/// 这类布局的经典翻车方式是**溢出**（RenderFlex overflow）—— 真机上表现为
/// 一条黄黑条纹，代码里完全看不出来。`tester.takeException()` 能把它抓住。
///
/// 另外"跨节的课只画一块"这种要求，也只有数一数 widget 的个数才验证得了。
void main() {
  menuTests();

  group('周视图网格', () {
    testWidgets('表头按实际用到的天数画（周一到周五）', (WidgetTester tester) async {
      await _pump(
        tester,
        courses: _weekdayCourses(<int>[1, 2, 3, 4, 5]),
        schedule: _schedule(),
      );

      expect(find.text('周一'), findsOneWidget);
      expect(find.text('周五'), findsOneWidget);
      expect(find.text('周六'), findsNothing, reason: '周六没课就不该画那一列');
    });

    testWidgets('周六有课就自动多一列', (WidgetTester tester) async {
      await _pump(
        tester,
        courses: _weekdayCourses(<int>[1, 2, 3, 4, 5, 6]),
        schedule: _schedule(),
      );

      expect(find.text('周六'), findsOneWidget);
    });

    testWidgets('课程名和教室都画出来', (WidgetTester tester) async {
      await _pump(
        tester,
        courses: <Course>[
          _course(weekday: 2, start: 1, end: 1, name: '材料力学', location: '教学楼 A101'),
        ],
        schedule: _schedule(),
      );

      expect(find.text('材料力学'), findsOneWidget);
      expect(find.text('教学楼 A101'), findsOneWidget);
    });

    testWidgets('★ 跨节的课只画一块，不是每行各画一块', (WidgetTester tester) async {
      await _pump(
        tester,
        courses: <Course>[
          _course(weekday: 1, start: 1, end: 2, name: '流体力学', location: '实验楼 203'),
        ],
        schedule: _schedule(),
      );

      expect(find.text('流体力学'), findsOneWidget);
      expect(find.text('实验楼 203'), findsOneWidget);
    });

    testWidgets('★ 跨午休的课也只画一块（中间夹着午休也不能断成两截）',
        (WidgetTester tester) async {
      await _pump(
        tester,
        courses: <Course>[
          // 第 4 节（上午最后一节）连到第 5 节（下午第一节）—— 中间就是午休
          _course(weekday: 3, start: 4, end: 5, name: '连堂课'),
        ],
        schedule: _schedule(),
      );

      expect(find.text('连堂课'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('典型课表：左侧节次栏写出节次和时刻，午休有标记', (WidgetTester tester) async {
      await _pump(
        tester,
        courses: _weekdayCourses(<int>[1, 2, 3, 4, 5]),
        schedule: _schedule(),
      );

      expect(find.text('1'), findsOneWidget, reason: '节次号');
      expect(find.text('08:00'), findsOneWidget, reason: '第一节的开始时刻');
      expect(find.text('午休'), findsOneWidget, reason: '光有空档会让人以为漏画了一行');
    });

    testWidgets('有晚自习 → 网格下面画一条时间条，且不往里填课',
        (WidgetTester tester) async {
      await _pump(
        tester,
        courses: _weekdayCourses(<int>[1, 2]),
        schedule: _schedule(eveningStart: 19 * 60, eveningEnd: 21 * 60 + 30),
      );

      expect(find.text('晚自习'), findsOneWidget);
      expect(find.text('19:00~21:30'), findsOneWidget);
    });

    testWidgets('没有晚自习 → 不画时间条', (WidgetTester tester) async {
      await _pump(
        tester,
        courses: _weekdayCourses(<int>[1, 2]),
        schedule: _schedule(),
      );

      expect(find.text('晚自习'), findsNothing);
    });

    testWidgets('★ 窄屏 + 7 列 + 长课名 + 单节格子，不溢出', (WidgetTester tester) async {
      // 这是最紧的一档：列最窄、格子最矮、课名最长。
      // 溢出在真机上是一条黄黑条纹，代码审查看不出来 —— 靠 takeException 抓。
      await _pump(
        tester,
        width: 360,
        courses: <Course>[
          _course(
            weekday: 1,
            start: 1,
            end: 1,
            name: '马克思主义基本原理概论',
            location: '第三教学楼 B 区 502',
          ),
          _course(weekday: 6, start: 2, end: 2, name: '体育', location: '田径场'),
          _course(weekday: 7, start: 3, end: 4, name: '结构力学基础', location: '机房 2'),
        ],
        schedule: _schedule(),
      );

      expect(find.text('周日'), findsOneWidget, reason: '7 列全画出来');
      expect(tester.takeException(), isNull);
    });

    testWidgets('一节课都没有时不崩，也不画网格', (WidgetTester tester) async {
      await _pump(
        tester,
        courses: const <Course>[],
        schedule: const TimetableSchedule(),
      );

      expect(find.text('周一'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('脏数据（起止节次反了）不崩', (WidgetTester tester) async {
      await _pump(
        tester,
        courses: <Course>[_course(weekday: 1, start: 5, end: 3, name: '坏数据')],
        schedule: _schedule(),
      );

      expect(tester.takeException(), isNull);
    });
  });
}

// ---------------------------------------------------------------------------
// 夹具
// ---------------------------------------------------------------------------

/// 三点点菜单（2026-10-07 接上的交互层）—— 组件测试
void menuTests() {
  group('三点点菜单', () {
    testWidgets('★ 不传回调时没有三个点 —— 只读模式保持原样', (WidgetTester tester) async {
      await _pump(
        tester,
        courses: <Course>[_course(weekday: 1, start: 1, end: 2, name: '甲课')],
        schedule: _schedule(),
      );
      expect(find.byIcon(Icons.more_horiz), findsNothing);
    });

    testWidgets('★ 传了回调，每格右上角出现三个点，点它回调带课程和锚点', (
      WidgetTester tester,
    ) async {
      Course? tapped;
      Rect? anchor;
      await _pump(
        tester,
        courses: <Course>[_course(weekday: 1, start: 1, end: 2, name: '甲课')],
        schedule: _schedule(),
        onCellMenu: (Course course, Rect a) {
          tapped = course;
          anchor = a;
        },
      );

      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_horiz));
      expect(tapped?.name, '甲课');
      expect(anchor, isNotNull);
      expect(anchor!.width, greaterThan(0));
    });

    testWidgets('★ 点空白格回调「第几节」—— 加课的入口', (WidgetTester tester) async {
      int? tappedWeekday;
      int? tappedPeriod;
      await _pump(
        tester,
        // 只有周一 1-2 节有课；点最后一列的空白
        courses: <Course>[_course(weekday: 1, start: 1, end: 2, name: '甲课')],
        schedule: _schedule(),
        onEmptyCellMenu: (int weekday, int period, Rect a) {
          tappedWeekday = weekday;
          tappedPeriod = period;
        },
      );

      // 周一列第 4 节的行中心（1-2 节被甲课占着，4 是空白）：
      // 卡内 padding 6 + 表头 32，每行 58，第 4 节行顶 = 3×58 = 174，+29 取行中心
      final Rect grid = tester.getRect(find.byType(WeekGridView));
      final Offset headerCenter = tester.getCenter(find.text('周一'));
      await tester.tapAt(
        Offset(headerCenter.dx, grid.top + 6 + 32 + 174 + 29),
      );

      expect(tappedWeekday, 1, reason: '点的是周一那一列');
      expect(tappedPeriod, 4, reason: 'y 落在第 4 节的行带里');
    });

    testWidgets('★ 点在有课的格子主体上不触发空白加课', (WidgetTester tester) async {
      bool emptyCalled = false;
      await _pump(
        tester,
        courses: <Course>[_course(weekday: 1, start: 1, end: 2, name: '甲课')],
        schedule: _schedule(),
        onEmptyCellMenu: (int weekday, int period, Rect a) =>
            emptyCalled = true,
      );

      await tester.tap(find.text('甲课'), warnIfMissed: false);
      expect(emptyCalled, isFalse,
          reason: '格子盖在空白点击层上面，点到格子不该算空白');
    });

    testWidgets('点在午休缝上不响应（午休不属于任何一节）', (WidgetTester tester) async {
      int? tappedPeriod;
      await _pump(
        tester,
        courses: <Course>[],
        schedule: _schedule(),
        onEmptyCellMenu: (int weekday, int period, Rect a) =>
            tappedPeriod = period,
      );

      // 午休缝：4 行课后那 16px 的缝，中心 ≈ 6+32+4×58+8
      final Rect grid = tester.getRect(find.byType(WeekGridView));
      final Offset headerCenter = tester.getCenter(find.text('周一'));
      await tester.tapAt(
        Offset(headerCenter.dx, grid.top + 6 + 32 + 4 * 58 + 8),
      );
      expect(tappedPeriod, isNull);
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Course> courses,
  required TimetableSchedule schedule,
  double width = 440,
  void Function(Course course, Rect anchor)? onCellMenu,
  void Function(int weekday, int period, Rect anchor)? onEmptyCellMenu,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorSchemeSeed: const Color(0xFF3A6EA5)),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: SizedBox(
              width: width,
              child: WeekGridView(
                courses: courses,
                schedule: schedule,
                onCellMenu: onCellMenu,
                onEmptyCellMenu: onEmptyCellMenu,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 典型中学课表：上午 4 节 8:00~11:40，下午 4 节 14:00~17:30，每节 45 分钟
TimetableSchedule _schedule({int? eveningStart, int? eveningEnd}) =>
    buildSchedule(
      ScheduleAnchors(
        firstStartMinute: 8 * 60,
        morningEndMinute: 11 * 60 + 40,
        afternoonStartMinute: 14 * 60,
        lastEndMinute: 17 * 60 + 30,
        periodMinutes: 45,
        morningPeriodCount: 4,
        afternoonPeriodCount: 4,
        eveningStartMinute: eveningStart,
        eveningEndMinute: eveningEnd,
      ),
    );

List<Course> _weekdayCourses(List<int> weekdays) => <Course>[
      for (final int d in weekdays)
        _course(weekday: d, start: 1, end: 1, name: '周$d 的课'),
    ];

Course _course({
  required int weekday,
  required int start,
  required int end,
  required String name,
  String location = '',
}) =>
    Course(
      id: 0,
      weekday: weekday,
      startPeriod: start,
      endPeriod: end,
      name: name,
      location: location,
      createdAt: DateTime(2026, 10, 7),
    );
