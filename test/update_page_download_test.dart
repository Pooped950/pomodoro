import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/app_info.dart';
import 'package:pomodoro/domain/update/update_decision.dart';
import 'package:pomodoro/domain/update/update_info.dart';
import 'package:pomodoro/presentation/pages/update/update_page.dart';
import 'package:pomodoro/presentation/providers/update_provider.dart';

import 'support/update_fakes.dart';

/// 「检查更新」页在**下载/安装各阶段**画出来的东西。
///
/// 用法：直接把状态喂给页面（`FakeUpdateNotifier`），不去点按钮 ——
/// 状态机的语义在 `update_download_flow_test.dart` 里测，这里只关心"画对了没"。
void main() {
  final String sha = List<String>.filled(64, 'd').join();

  UpdateInfo info({required int versionCode}) => UpdateInfo(
        versionCode: versionCode,
        versionName: '9.9.9',
        apkUrl: 'https://gitee.com/o/r/raw/main/a.apk',
        sha256: sha,
        sizeBytes: 1024,
      );

  Future<void> pump(WidgetTester tester, UpdateState state) async {
    // 页面比默认测试画布高：不放大画布，ListView 懒加载不会建出下面的控件
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateStateProvider.overrideWith(() => FakeUpdateNotifier(state)),
        ],
        child: const MaterialApp(home: UpdatePage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('下载中 → 显示百分比 + 进度条 + 取消', (WidgetTester tester) async {
    await pump(
      tester,
      UpdateState(
        remote: info(versionCode: kAppVersionCode + 1),
        action: UpdateAction.silentHint,
        progress: 0.6,
      ),
    );

    expect(find.textContaining('60%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    // 正在下载时不该再出现「立即更新」
    expect(find.widgetWithText(FilledButton, '立即更新'), findsNothing);
  });

  testWidgets('下载完成 → 主按钮变成「安装」', (WidgetTester tester) async {
    await pump(
      tester,
      UpdateState(
        remote: info(versionCode: kAppVersionCode + 1),
        action: UpdateAction.silentHint,
        downloadedPath: '/tmp/updates/a.apk',
      ),
    );

    expect(find.widgetWithText(FilledButton, '安装'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '立即更新'), findsNothing);
  });

  testWidgets('下载失败 → 页内提示 + 重试', (WidgetTester tester) async {
    await pump(
      tester,
      UpdateState(
        remote: info(versionCode: kAppVersionCode + 1),
        action: UpdateAction.silentHint,
        downloadError: '下载校验失败，请重试',
      ),
    );

    expect(find.text('下载校验失败，请重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('缺「安装未知应用」授权 → 提示 + 去设置允许', (WidgetTester tester) async {
    await pump(
      tester,
      UpdateState(
        remote: info(versionCode: kAppVersionCode + 1),
        action: UpdateAction.silentHint,
        downloadedPath: '/tmp/updates/a.apk',
        installHint: '需要先允许「安装未知应用」',
        needsInstallPermission: true,
      ),
    );

    expect(find.text('需要先允许「安装未知应用」'), findsOneWidget);
    expect(find.text('去设置允许'), findsOneWidget);
  });

  testWidgets('装不了 → 只给一句人话，不给"去设置"（免得白跑一趟）',
      (WidgetTester tester) async {
    await pump(
      tester,
      UpdateState(
        remote: info(versionCode: kAppVersionCode + 1),
        action: UpdateAction.silentHint,
        downloadedPath: '/tmp/updates/a.apk',
        installHint: '这个系统不让直接装，去发布页下载安装吧',
      ),
    );

    expect(find.text('这个系统不让直接装，去发布页下载安装吧'), findsOneWidget);
    expect(find.text('去设置允许'), findsNothing);
  });
}
