import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/app_info.dart';
import 'package:pomodoro/domain/update/update_decision.dart';
import 'package:pomodoro/domain/update/update_info.dart';
import 'package:pomodoro/presentation/pages/update/update_page.dart';
import 'package:pomodoro/presentation/providers/update_provider.dart';

import 'support/update_fakes.dart';

/// 「检查更新」页的四种**检查**状态 —— 这是用户唯一会盯着的界面，
/// 状态和文案错一个他就要来问"到底有没有新版"。
/// （下载/安装那一段在 `update_page_download_test.dart`）
void main() {
  final String sha = List<String>.filled(64, 'd').join();

  UpdateInfo info({
    required int versionCode,
    List<String> notes = const <String>[],
    String? downloadPage = 'https://gitee.com/o/r',
  }) =>
      UpdateInfo(
        versionCode: versionCode,
        versionName: '9.9.9',
        apkUrl: 'https://gitee.com/o/r/raw/main/a.apk',
        sha256: sha,
        sizeBytes: 1024,
        notes: notes,
        downloadPage: downloadPage,
      );

  Future<void> pump(
    WidgetTester tester,
    UpdateState state, {
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateStateProvider.overrideWith(() => FakeUpdateNotifier(state)),
        ],
        child: const MaterialApp(home: UpdatePage()),
      ),
    );
    // 「检查中」有个不停转的圈：pumpAndSettle 永远等不到静止
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('检查中 → 显示进度指示', (WidgetTester tester) async {
    await pump(tester, const UpdateState(checking: true), settle: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('已是最新 → 文案「已是最新」，主按钮置灰', (WidgetTester tester) async {
    await pump(
      tester,
      UpdateState(
        remote: info(versionCode: kAppVersionCode),
        checkedAt: DateTime(2026, 10, 7, 18),
        action: UpdateAction.none,
      ),
    );

    expect(find.text('已是最新'), findsOneWidget);
    final FilledButton button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '立即更新'),
    );
    expect(button.onPressed, isNull, reason: '没新版本时按钮该置灰');
  });

  testWidgets('有新版本 → 显示远端版本号 + 更新说明每一条，按钮可点',
      (WidgetTester tester) async {
    await pump(
      tester,
      UpdateState(
        remote: info(
          versionCode: kAppVersionCode + 1,
          notes: <String>['甲：课表更准了', '乙：多了三点点菜单'],
        ),
        checkedAt: DateTime(2026, 10, 7, 18),
        action: UpdateAction.showPrompt,
      ),
    );

    expect(find.textContaining('9.9.9'), findsWidgets);
    expect(find.text('甲：课表更准了'), findsOneWidget);
    expect(find.text('乙：多了三点点菜单'), findsOneWidget);

    final FilledButton button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '立即更新'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('检查失败 → 页内提示 + 重试按钮（不是弹窗）', (WidgetTester tester) async {
    await pump(tester, const UpdateState(error: '检查失败，稍后再试'));

    expect(find.text('检查失败，稍后再试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('有 downloadPage → 显示「打开发布页」', (WidgetTester tester) async {
    await pump(tester,
        UpdateState(remote: info(versionCode: kAppVersionCode + 1)));

    expect(find.text('打开发布页'), findsOneWidget);
  });

  testWidgets('没有 downloadPage → 不显示「打开发布页」', (WidgetTester tester) async {
    await pump(
      tester,
      UpdateState(
          remote: info(versionCode: kAppVersionCode + 1, downloadPage: null)),
    );

    expect(find.text('打开发布页'), findsNothing);
  });
}
