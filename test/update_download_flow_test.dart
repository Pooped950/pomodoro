import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/app_info.dart';
import 'package:pomodoro/data/repositories/settings_repository.dart';
import 'package:pomodoro/data/services/apk_downloader.dart';
import 'package:pomodoro/data/services/apk_installer.dart';
import 'package:pomodoro/data/services/update_service.dart';
import 'package:pomodoro/presentation/providers/update_provider.dart';

import 'support/update_fakes.dart';

/// 下载 → 安装这条链的**语义**。
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
  }) async {
    final ProviderContainer c =
        container(body: body, downloader: downloader, installer: installer);
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

  test('★ 节流窗口内再检查 → 不是「检查失败」，显示缓存里的最新版（评审 C1）',
      () async {
    // 造出"10 分钟内刚检查过"的现场：启动检查记录 lastCheckAt，用户随后打开页面
    store.values[SettingsRepository.keyUpdateLastCheckAt] =
        DateTime.now().toIso8601String();
    store.values[SettingsRepository.keyUpdateCachedJson] =
        versionJson(versionCode: kAppVersionCode + 1, versionName: '9.9.9');

    final ProviderContainer c = ProviderContainer(
      overrides: [
        updateServiceProvider.overrideWithValue(UpdateService(
          store: store,
          // 节流窗口内**根本不该发请求**：真发了就让这个测试炸
          fetcher: (String url) async => throw StateError('节流窗口内不该发请求'),
          endpoint: 'https://example.test/version.json',
        )),
        apkDownloaderProvider.overrideWithValue(FakeDownloader()),
        apkInstallerProvider.overrideWithValue(FakeInstaller()),
        updateTempDirProvider.overrideWith((Ref ref) async => tmp),
      ],
    );
    addTearDown(c.dispose);

    await c.read(updateStateProvider.notifier).checkIfStale();

    final UpdateState s = c.read(updateStateProvider);
    expect(s.error, isNull, reason: '被节流跳过不是失败，不能报「检查失败」');
    expect(s.remote?.versionName, '9.9.9', reason: '该显示上次缓存到的最新版本');
  });

  test('★ 远端换了版本 → 之前下好的包作废，不再显示「安装」（评审 I4）', () async {
    String body = versionJson(versionCode: kAppVersionCode + 1, sizeBytes: 5);
    final ProviderContainer c = ProviderContainer(
      overrides: [
        updateServiceProvider.overrideWithValue(UpdateService(
          store: store,
          fetcher: (String url) async => body,
          endpoint: 'https://example.test/version.json',
        )),
        apkDownloaderProvider.overrideWithValue(FakeDownloader()),
        apkInstallerProvider.overrideWithValue(FakeInstaller()),
        updateTempDirProvider.overrideWith((Ref ref) async => tmp),
      ],
    );
    addTearDown(c.dispose);

    await c.read(updateStateProvider.notifier).checkNow();
    await c.read(updateStateProvider.notifier).startDownload();
    await waitFor(c, (UpdateState s) => s.downloadedPath != null);

    // 远端又发了一版
    body = versionJson(
        versionCode: kAppVersionCode + 2, versionName: '9.9.10', sizeBytes: 5);
    await c.read(updateStateProvider.notifier).checkNow();

    final UpdateState s = c.read(updateStateProvider);
    expect(s.remote?.versionCode, kAppVersionCode + 2);
    expect(s.downloadedPath, isNull,
        reason: '旧包不能当新版递给用户去装');
  });

  test('取消下载 → 进度归零，且不留"可安装"的包', () async {
    // 用 broadcast：单订阅的 controller 在「yield* 转发 + 取消」时可能卡住
    final StreamController<ApkDownloadProgress> chunks =
        StreamController<ApkDownloadProgress>.broadcast();
    addTearDown(chunks.close);
    final ProviderContainer c = await ready(
      body: versionJson(versionCode: kAppVersionCode + 1, sizeBytes: 5),
      downloader: FakeDownloader(stream: chunks.stream),
    );

    await c.read(updateStateProvider.notifier).startDownload();
    await c.read(updateStateProvider.notifier).cancelDownload();

    final UpdateState s = c.read(updateStateProvider);
    expect(s.downloading, isFalse);
    expect(s.downloadedPath, isNull);
  });
}
