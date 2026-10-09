import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/data/services/class_reminder_service.dart';
import 'package:pomodoro/presentation/pages/settings/settings_detail_page.dart';
import 'package:pomodoro/presentation/providers/class_reminder_provider.dart';
import 'package:pomodoro/presentation/widgets/app_card.dart';

/// 设置页「课表」那张卡 —— 钉住 2026-10-09 修的两个 bug：
///
///   1. **开关名不副实**：第一行原来叫「上课提醒」，但它绑的是 `vibrate`。
///      用户想"关掉上课提醒"会关它，可「响铃」还开着 —— 照样响。
///      现在两个开关叫「震动」「响铃」，和上面番茄钟那组一致。
///   2. **精确闹钟静默降级**：Android 12 只有 `SCHEDULE_EXACT_ALARM` 且必须用户
///      手动开，拿不到时提醒会晚几分钟到十几分钟 —— 原来完全没提示。
///      现在卡里会多出一条「精确提醒未开启」，点一下跳系统授权页。
class _FakeService extends ClassReminderService {
  const _FakeService({required this.exact});

  /// 系统有没有放行精确闹钟
  final bool exact;

  @override
  Future<bool> canScheduleExact() async => exact;

  @override
  Future<int> count() async => 0;
}

void main() {
  Future<void> pump(WidgetTester tester, {required bool exact}) async {
    // 设置页比默认测试画布高：不放大画布，ListView 懒加载不会建出课表那张卡
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          classReminderServiceProvider.overrideWithValue(_FakeService(exact: exact)),
        ],
        child: const MaterialApp(home: SettingsDetailPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 课表那张卡（用只在它里面出现的副标题定位，避免和番茄钟那组的「震动」撞名）
  Finder classCard() => find.ancestor(
        of: find.text('关掉就只震动，不响铃'),
        matching: find.byType(AppCard),
      );

  testWidgets('★ 课表两个开关叫「震动」「响铃」，不再有「上课提醒」这个总开关',
      (WidgetTester tester) async {
    await pump(tester, exact: true);

    expect(find.descendant(of: classCard(), matching: find.text('震动')),
        findsOneWidget);
    expect(find.descendant(of: classCard(), matching: find.text('响铃')),
        findsOneWidget);
    expect(
      find.text('上课提醒'),
      findsNothing,
      reason: '这个开关只管震动 —— 叫「上课提醒」会让人以为关掉就不提醒了，'
          '而「响铃」还开着的时候照样响',
    );
  });

  testWidgets('★ 系统没放行精确闹钟 → 卡里出现「精确提醒未开启」', (WidgetTester tester) async {
    await pump(tester, exact: false);

    expect(
      find.descendant(of: classCard(), matching: find.text('精确提醒未开启')),
      findsOneWidget,
      reason: 'Android 12 拿不到精确闹钟时提醒会静默晚几分钟，必须让用户看得见',
    );
    expect(find.textContaining('闹钟与提醒'), findsOneWidget);
  });

  testWidgets('精确闹钟已放行 → 不出现那条提示', (WidgetTester tester) async {
    await pump(tester, exact: true);

    expect(find.text('精确提醒未开启'), findsNothing);
  });
}
