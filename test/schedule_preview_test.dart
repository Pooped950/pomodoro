import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/timetable/period_time.dart';
import 'package:pomodoro/presentation/pages/settings/schedule_preview.dart';

/// 「排出来是这样」预览卡的组件测试。
///
/// 钉住 2026-10-07 用户要求的交互：**还没输入任何东西时，预览整块
/// 淡显（0.45）并说明是默认值示意** —— 它是示意，不是拍板的结果。
void main() {
  const TimetableSchedule schedule = TimetableSchedule(
    periods: <PeriodTime>[
      PeriodTime(period: 1, startMinute: 480, endMinute: 525),
      PeriodTime(period: 2, startMinute: 535, endMinute: 580),
    ],
  );

  Future<void> pump(WidgetTester tester, {required bool dimmed}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFF3A6EA5)),
        home: Scaffold(
          body: SchedulePreview(schedule: schedule, dimmed: dimmed),
        ),
      ),
    );
  }

  testWidgets('未输入（dimmed）→ 整块淡显 + 默认值示意说明', (WidgetTester tester) async {
    await pump(tester, dimmed: true);

    final Opacity opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(SchedulePreview),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, 0.45);
    expect(
      find.text('这是预填默认值的示意 —— 改上面任意一项或粘贴作息表后会变'),
      findsOneWidget,
    );
  });

  testWidgets('输入过（不淡显）→ 正常浓度，没有示意说明', (WidgetTester tester) async {
    await pump(tester, dimmed: false);

    expect(find.byType(Opacity), findsNothing);
    expect(
      find.text('这是预填默认值的示意 —— 改上面任意一项或粘贴作息表后会变'),
      findsNothing,
    );
    expect(find.text('1·08:00-08:45'), findsOneWidget);
    expect(find.text('2·08:55-09:40'), findsOneWidget);
  });

  testWidgets('schedule 为 null → 显示格式错误提示（不淡显问题无关）', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFF3A6EA5)),
        home: const Scaffold(
          body: SchedulePreview(schedule: null, dimmed: true),
        ),
      ),
    );
    expect(find.text('时间还没填完整（格式要像 08:00）'), findsOneWidget);
  });
}
