import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/app_info.dart';
import 'package:pomodoro/presentation/pages/manual/manual_content.dart';
import 'package:pomodoro/presentation/pages/manual/manual_dialog.dart';

/// 使用手册弹窗的界面测试。
///
/// ## 为什么这几条必须测
///
/// 手册是"看一眼就关掉"的东西，出了问题（按钮跑到屏幕外、翻不动页）
/// 单靠代码审查看不出来 —— 第一版就真的把「继续」按钮排到了屏幕外，
/// 界面上完全看不见。这几条就是钉住这类问题。
Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(backgroundColor: Colors.white, body: child),
    );

void main() {
  testWidgets('★ 弹窗渲染出标题、页码、两个按钮（按钮不能在屏幕外）',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const ManualDialogBody(isFirstLaunch: true)));
    await tester.pumpAndSettle();

    // 标题（首启文案）
    expect(find.text('欢迎使用'), findsOneWidget);
    expect(find.text('v$kAppVersion'), findsOneWidget);

    // 第一页的内容
    expect(find.text('一颗番茄'), findsOneWidget);

    // 两个按钮都要**真实可见**：用 hitTestable 确认它落在了可点区域内，
    // 而不是被排到屏幕外（第一版就栽在这）
    expect(find.text('跳过').hitTestable(), findsOneWidget);
    expect(find.text('继续').hitTestable(), findsOneWidget);
  });

  testWidgets('★ 上下滑动能翻页', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const ManualDialogBody()));
    await tester.pumpAndSettle();

    expect(find.text('一颗番茄'), findsOneWidget);

    // 往上拖 = 翻到下一页
    await tester.drag(find.byType(PageView), const Offset(0, -320));
    await tester.pumpAndSettle();

    expect(find.text('计时'), findsOneWidget, reason: '往上拖应该翻到第二页');
  });

  testWidgets('点「继续」也能翻页，翻到最后一页变成「开始使用」',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const ManualDialogBody()));
    await tester.pumpAndSettle();

    final int total = manualPagesWithReleaseNotes().length;
    for (int i = 0; i < total - 1; i++) {
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
    }

    expect(find.text('开始使用'), findsOneWidget);
    expect(find.text('继续'), findsNothing);
  });

  testWidgets('从「关于」打开时不给「跳过」（那是首启才需要的东西）',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const ManualDialogBody()));
    await tester.pumpAndSettle();

    expect(find.text('使用手册'), findsOneWidget);
    expect(find.text('跳过'), findsNothing);
    expect(find.text('继续'), findsOneWidget);
  });

  testWidgets('每一页都能渲染出来，不抛异常', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const ManualDialogBody()));
    await tester.pumpAndSettle();

    for (final ManualPage p in manualPagesWithReleaseNotes()) {
      expect(
        find.text(p.title),
        findsOneWidget,
        reason: '「${p.title}」这一页渲染不出来',
      );
      await tester.drag(find.byType(PageView), const Offset(0, -320));
      await tester.pumpAndSettle();
    }
  });
}
