import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/app_info.dart';
import 'package:pomodoro/data/services/apk_downloader.dart';
import 'package:pomodoro/data/services/apk_installer.dart';
import 'package:pomodoro/data/services/update_service.dart';
import 'package:pomodoro/presentation/providers/update_provider.dart';

import 'support/update_fakes.dart';

/// 下载 → 安装这条链的**语义**（spec §7.4 / §7.5）。
///
/// 为什么测 notifier 而不是点界面上那些按钮：这段逻辑的状态机在 notifier 里，
/// 界面只是把状态画出来（那部分在 `update_page_test.dart` 用固定状态测）。
/// 交互式 widget 测试在这套动画 + ListView 懒加载上非常脆，收益不如直接测状态。
void main() {
  late Directory tmp;
  late FakeUpdateStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('upd_flow_test');
    store = FakeUpdateStore();
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  ProviderContainer container({
    required String body,
    FakeDownloader? downloader,
    FakeInstaller? installer,
    FreeSpaceProbe? probe,
  }) {
    final ProviderContainer c = ProviderContainer(
      overrides: [
        updateServiceProvider.overrideWithValue(UpdateService(
          store: store,
          fetcher: (String url) async => body,
          endpoint: 'https://example.test/version.json',
        )),
        apkDownloaderProvider.overrideWithValue(downloader ?? FakeDownloader()),
        apkInstallerProvider.overrideWithValue(installer ?? FakeInstaller()),
        updateTempDirProvider.overrideWith((Ref ref) async => tmp),
        updateFreeSpaceProvider.overrideWithValue(probe),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// 等状态满足条件（流式下载是异步的，不能只 await 一次）
  Future<UpdateState> waitFor(
    ProviderContainer c,
    bool Function(UpdateState s) ok, {
    String? reason,
  }) async {
    for (int i = 0; i < 200; i++) {
      final UpdateState s = c.read(updateStateProvider);
      if (ok(s)) return s;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('等不到期望状态${reason == null ? '' : '（$reason）'}：${c.read(updateStateProvider).downloadedPath} / ${c.read(updateStateProvider).downloadError}');
  }

  Future<ProviderContainer> ready({
    required String body,
    FakeDownloader? downloader,
    FakeInstaller? installer,
    FreeSpaceProbe? probe,
  }) async {
    final ProviderContainer c = container(
        body: body, downloader: downloader, installer: installer, probe: probe);
    await c.read(updateStateProvider.notifier).checkNow();
    return c;
  }

  test('下载成功 → downloadedPath 指向真实文件，进度归位', () async {
    final ProviderContainer c = await ready(
      body: versionJson(versionCode: kAppVersionCode + 1, sizeBytes: 5),
    );

    await c.read(updateStateProvider.notifier).startDownload();
    final UpdateState s =
        await waitFor(c, (UpdateState s) => s.downloadedPath != null);

    expect(s.downloading, isFalse);
    expect(s.downloadError, isNull);
    expect(File(s.downloadedPath!).existsSync(), isTrue);
    expect(File(s.downloadedPath!).readAsStringSync(), 'hello');
  });

  test('sha256 对不上 → 校验失败提示，且不留下"可安装"的路径', () async {
    final ProviderContainer c = await ready(
      body: versionJson(
          versionCode: kAppVersionCode + 1, sha256: kWrongSha, sizeBytes: 5),
    );

    await c.read(updateStateProvider.notifier).startDownload();
    final UpdateState s = await waitFor(
        c, (UpdateState s) => s.downloadError != null);

    expect(s.downloadError, '下载校验失败，请重试');
    expect(s.downloadedPath, isNull);
  });

  test('安装：缺授权 → 给出"去设置"的提示，并真的调了设置跳转', () async {
    final FakeInstaller installer = FakeInstaller(InstallStatus.needPermission);
    final ProviderContainer c = await ready(
      body: versionJson(versionCode: kAppVersionCode + 1, sizeBytes: 5),
      installer: installer,
    );

    await c.read(updateStateProvider.notifier).startDownload();
    await waitFor(c, (UpdateState s) => s.downloadedPath != null);
    await c.read(updateStateProvider.notifier).installDownloaded();

    final UpdateState s = c.read(updateStateProvider);
    expect(installer.installCalls, 1);
    expect(s.needsInstallPermission, isTrue);
    expect(s.installHint, '需要先允许「安装未知应用」');

    await c.read(updateStateProvider.notifier).openInstallPermissionSettings();
    expect(installer.settingsCalls, 1);
  });

  test('装不了（ROM 拦）→ 给一句人话，不留下"缺权限"的误导', () async {
    final ProviderContainer c = await ready(
      body: versionJson(versionCode: kAppVersionCode + 1, sizeBytes: 5),
      installer: FakeInstaller(InstallStatus.unsupported),
    );

    await c.read(updateStateProvider.notifier).startDownload();
    await waitFor(c, (UpdateState s) => s.downloadedPath != null);
    await c.read(updateStateProvider.notifier).installDownloaded();

    final UpdateState s = c.read(updateStateProvider);
    expect(s.needsInstallPermission, isFalse);
    expect(s.installHint, '这个系统不让直接装，去发布页下载安装吧');
  });

  test('重新检查不会把已经下好的包弄丢、也不再下一次', () async {
    final FakeDownloader downloader = FakeDownloader();
    final ProviderContainer c = await ready(
      body: versionJson(versionCode: kAppVersionCode + 1, sizeBytes: 5),
      downloader: downloader,
    );

    await c.read(updateStateProvider.notifier).startDownload();
    final UpdateState first =
        await waitFor(c, (UpdateState s) => s.downloadedPath != null);

    await c.read(updateStateProvider.notifier).checkNow();

    final UpdateState after = c.read(updateStateProvider);
    expect(after.downloadedPath, first.downloadedPath);
    expect(downloader.calls, 1, reason: '已经下好了就不该再下一次');
  });

  test('空间不足 → 提示且根本不开始下载', () async {
    final FakeDownloader downloader = FakeDownloader();
    final ProviderContainer c = await ready(
      body: versionJson(versionCode: kAppVersionCode + 1, sizeBytes: 100),
      downloader: downloader,
      probe: () async => 1,
    );

    await c.read(updateStateProvider.notifier).startDownload();

    expect(c.read(updateStateProvider).downloadError, '手机剩余空间不足，先清一点再更新');
    expect(downloader.calls, 0);
  });

  test('包在服务器上不存在（404）→ 翻译成人话', () async {
    final ProviderContainer c = await ready(
      body: versionJson(versionCode: kAppVersionCode + 1, sizeBytes: 5),
      downloader: FakeDownloader(
          error: const ApkDownloadException('下载失败（HTTP 404）')),
    );

    await c.read(updateStateProvider.notifier).startDownload();
    final UpdateState s = await waitFor(
        c, (UpdateState s) => s.downloadError != null);

    expect(s.downloadError, '服务器上没有这个包，去发布页看看');
  });

  test('导出/磁盘写满（ENOSPC）→ 翻译成"空间不足"', () async {
    final ProviderContainer c = await ready(
      body: versionJson(versionCode: kAppVersionCode + 1, sizeBytes: 5),
      downloader: FakeDownloader(
          error: const ApkDownloadException(
              '下载出错：FileSystemException: write failed, errno = 28 (ENOSPC)')),
    );

    await c.read(updateStateProvider.notifier).startDownload();
    final UpdateState s = await waitFor(
        c, (UpdateState s) => s.downloadError != null);

    expect(s.downloadError, '手机剩余空间不足，先清一点再更新');
  });
}
