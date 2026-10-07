import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/app_info.dart';
import '../../data/services/apk_downloader.dart';
import '../../data/services/apk_installer.dart';
import '../../data/services/update_service.dart';
import '../../domain/update/update_decision.dart';
import '../../domain/update/update_info.dart';

/// 「检查更新」的界面状态 —— UI 只读它，判断逻辑全在 [UpdateNotifier] 里。
@immutable
class UpdateState {
  const UpdateState({
    this.remote,
    this.checkedAt,
    this.checking = false,
    this.error,
    this.action = UpdateAction.none,
    this.progress,
    this.downloadedPath,
    this.downloadError,
    this.installHint,
    this.needsInstallPermission = false,
  });

  /// 已知的最新版本（本次拉到的，或上次成功的缓存）
  final UpdateInfo? remote;

  /// 上次发起检查的时间（成功失败都记）
  final DateTime? checkedAt;

  /// 正在检查（按钮转圈用）
  final bool checking;

  /// 检查失败的提示；成功时为 null
  final String? error;

  /// 启动时该做什么（由纯函数 [decideUpdate] 算出来）
  final UpdateAction action;

  /// 下载进度 0..1；**null = 没在下载**
  final double? progress;

  /// 已经下载并校验通过的 APK 路径（有它就显示「安装」）
  final String? downloadedPath;

  /// 下载/校验失败的提示
  final String? downloadError;

  /// 安装那一步要告诉用户的话（缺授权 / 装不了）
  final String? installHint;

  /// 上次安装尝试的结论是"缺「安装未知应用」授权"（界面给一个去设置的按钮）
  final bool needsInstallPermission;

  /// 有比当前更新的版本（小红点看它）
  bool get hasNewer =>
      remote != null && remote!.versionCode > kAppVersionCode;

  /// 正在下载（进度非 null）
  bool get downloading => progress != null;

  UpdateState copyWith({
    UpdateInfo? remote,
    DateTime? checkedAt,
    bool? checking,
    String? error,
    UpdateAction? action,
    double? progress,
    String? downloadedPath,
    String? downloadError,
    String? installHint,
    bool? needsInstallPermission,
    bool clearError = false,
    bool clearProgress = false,
    bool clearDownloadError = false,
    bool clearInstallHint = false,
  }) =>
      UpdateState(
        remote: remote ?? this.remote,
        checkedAt: checkedAt ?? this.checkedAt,
        checking: checking ?? this.checking,
        error: clearError ? null : (error ?? this.error),
        action: action ?? this.action,
        progress: clearProgress ? null : (progress ?? this.progress),
        downloadedPath: downloadedPath ?? this.downloadedPath,
        downloadError:
            clearDownloadError ? null : (downloadError ?? this.downloadError),
        installHint: clearInstallHint ? null : (installHint ?? this.installHint),
        needsInstallPermission:
            needsInstallPermission ?? this.needsInstallPermission,
      );
}

/// 生产环境在 `main()` 里 override 成真实实例（和 settingsRepositoryProvider 同款）
final updateServiceProvider = Provider<UpdateService>(
  (Ref ref) => throw UnimplementedError(
    'updateServiceProvider 必须在 main() 里 override',
  ),
);

/// 下载器 / 安装桥接：测试里 override 成假的，界面测试就不用碰网络和原生
final apkDownloaderProvider =
    Provider<ApkDownloader>((Ref ref) => ApkDownloader());
final apkInstallerProvider =
    Provider<ApkInstaller>((Ref ref) => ApkInstaller());

/// APK 落盘目录（临时目录；FileProvider 只暴露它下面的 `updates/`）
final updateTempDirProvider =
    FutureProvider<Directory>((Ref ref) => getTemporaryDirectory());

/// 可用空间探测。
///
/// Flutter 没有跨平台的磁盘空间 API，所以默认是 **null = 不做预检查**，
/// 改成把写入失败（ENOSPC）翻译成"空间不足"。测试可以注入假探测来验那段逻辑。
typedef FreeSpaceProbe = Future<int> Function();

final updateFreeSpaceProvider = Provider<FreeSpaceProbe?>((Ref ref) => null);

final updateStateProvider =
    NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);

/// 检查更新的状态机：检查 → 下载 → 安装，三段的失败都翻译成用户能懂的话。
///
/// 为什么不用 FutureProvider：这里要**显式**区分"正在检查 / 成功 / 失败"，
/// 而且失败时还得保留上次的缓存 —— 用 Notifier 手写这些状态最直白。
class UpdateNotifier extends Notifier<UpdateState> {
  @override
  UpdateState build() {
    // 先把上次成功的缓存显示出来（离线也能看到"上次看到的最新版"），
    // 不阻塞首帧：build 是同步的。
    unawaited(_refreshFromCache());
    ref.onDispose(() => unawaited(_sub?.cancel()));
    return const UpdateState();
  }

  /// 手动点「检查更新」：忽略节流，一定要发请求
  Future<void> checkNow() => _run(force: true);

  /// 进「我的」页时调用：走 10 分钟节流，不额外打扰网络
  Future<void> checkIfStale() => _run(force: false);

  /// 记下"这个版本的更新说明已经弹过了"，避免下次启动再弹
  Future<void> markPrompted() async {
    final UpdateInfo? remote = state.remote;
    if (remote == null) return;
    await _service.markPrompted(remote.versionCode);
    _prompted = remote.versionCode;
    await _refreshState();
  }

  // ------------------------------------------------------------------
  // 下载
  // ------------------------------------------------------------------

  /// 点「立即更新」：下载到临时目录并校验 sha256
  Future<void> startDownload() async {
    final UpdateInfo? info = state.remote;
    if (info == null || state.downloading) return;

    final Directory dir;
    try {
      dir = await ref.read(updateTempDirProvider.future);
    } catch (_) {
      state = state.copyWith(downloadError: '下载失败，请重试');
      return;
    }

    final FreeSpaceProbe? probe = ref.read(updateFreeSpaceProvider);
    if (probe != null) {
      try {
        final int free = await probe();
        // 留 100MB 余量：装包阶段系统还要占空间
        if (free < info.sizeBytes + 100 * 1024 * 1024) {
          state = state.copyWith(downloadError: '手机剩余空间不足，先清一点再更新');
          return;
        }
      } catch (_) {
        // 探测失败就照常下载：宁可让写入失败来兜底
      }
    }

    final String dest =
        '${dir.path}/updates/pomodoro-${info.versionName}.apk';
    state = state.copyWith(
      progress: 0,
      downloadedPath: null,
      clearDownloadError: true,
      clearInstallHint: true,
    );

    _sub = ref
        .read(apkDownloaderProvider)
        .download(
          url: info.apkUrl,
          destPath: dest,
          expectedSize: info.sizeBytes,
        )
        .listen(
      (ApkDownloadProgress p) {
        if (!ref.mounted) return;
        state = state.copyWith(progress: p.fraction);
      },
      onError: (Object e) {
        if (!ref.mounted) return;
        state = state.copyWith(
          clearProgress: true,
          downloadError: _downloadErrorMessage(e),
        );
      },
      onDone: () => unawaited(_finishDownload(dest, info.sha256)),
      cancelOnError: true,
    );
  }

  /// 用户点「取消」：停掉下载，进度归零（已下载的 .part 由下载器自己清）
  Future<void> cancelDownload() async {
    await _sub?.cancel();
    _sub = null;
    if (!ref.mounted) return;
    state = state.copyWith(clearProgress: true);
  }

  Future<void> _finishDownload(String dest, String sha256) async {
    final bool ok = await verifyApkSha256(dest, sha256);
    if (!ref.mounted) return;
    if (!ok) {
      try {
        final File f = File(dest);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {
        // 删不掉也不影响结论
      }
      state = state.copyWith(
        clearProgress: true,
        downloadError: '下载校验失败，请重试',
      );
      return;
    }
    state = state.copyWith(clearProgress: true, downloadedPath: dest);
  }

  // ------------------------------------------------------------------
  // 安装
  // ------------------------------------------------------------------

  /// 点「安装」：把下载好的包交给系统安装器
  Future<void> installDownloaded() async {
    final String? path = state.downloadedPath;
    if (path == null) return;

    final InstallStatus status =
        await ref.read(apkInstallerProvider).install(path);
    if (!ref.mounted) return;

    switch (status) {
      case InstallStatus.started:
        // 安装界面已经起来了，剩下的交给系统
        state = state.copyWith(clearInstallHint: true, needsInstallPermission: false);
      case InstallStatus.needPermission:
        state = state.copyWith(
          installHint: '需要先允许「安装未知应用」',
          needsInstallPermission: true,
        );
      case InstallStatus.unsupported:
        state = state.copyWith(
          installHint: '这个系统不让直接装，去发布页下载安装吧',
          needsInstallPermission: false,
        );
    }
  }

  /// 跳到系统「安装未知应用」授权页
  Future<void> openInstallPermissionSettings() =>
      ref.read(apkInstallerProvider).openInstallPermissionSettings();

  /// 用浏览器打开发布页（新人自助下载的那个页面）
  Future<void> openDownloadPage() async {
    final String? url = state.remote?.downloadPage;
    if (url == null) return;
    await ref.read(apkInstallerProvider).openDownloadPage(url);
  }

  // ------------------------------------------------------------------
  // 检查
  // ------------------------------------------------------------------

  Future<void> _run({required bool force}) async {
    state = state.copyWith(checking: true, clearError: true);
    final UpdateInfo? fresh = await _service.check(force: force);
    await _collect(fresh: fresh, failed: fresh == null);
  }

  Future<void> _refreshFromCache() async {
    await _ensureWarmUp();
    if (!ref.mounted) return;
    await _refreshState();
  }

  /// 用「本次拿到的 ?? 上次缓存」刷新状态
  Future<void> _collect(
      {required UpdateInfo? fresh, required bool failed}) async {
    await _ensureWarmUp();
    if (!ref.mounted) return;
    final UpdateInfo? remote = fresh ?? _service.cached;
    state = UpdateState(
      remote: remote,
      checkedAt: _service.lastCheckAt,
      checking: false,
      error: failed ? '检查失败，稍后再试' : null,
      action: _decide(remote),
      // 下载/安装的中间状态跨过一次检查要保留：用户可能边下边点了重新检查
      progress: state.progress,
      downloadedPath: state.downloadedPath,
      downloadError: state.downloadError,
      installHint: state.installHint,
      needsInstallPermission: state.needsInstallPermission,
    );
  }

  /// 只重算 action（弹过之后降级用），不改变 remote/checkedAt
  Future<void> _refreshState() async {
    state = state.copyWith(
      checkedAt: _service.lastCheckAt,
      checking: false,
      action: _decide(state.remote),
    );
  }

  Future<void> _ensureWarmUp() => _warmUpFuture ??= _doWarmUp();

  Future<void> _doWarmUp() async {
    await _service.warmUp();
    _prompted = await _service.promptedVersionCode();
  }

  static String _downloadErrorMessage(Object e) {
    final String s = e.toString();
    if (s.contains('ENOSPC') || s.contains('No space left')) {
      return '手机剩余空间不足，先清一点再更新';
    }
    if (s.contains('HTTP 404') || s.contains('HTTP 403')) {
      return '服务器上没有这个包，去发布页看看';
    }
    return '下载失败，请重试';
  }

  /// 预热只跑一次：把 future 存下来，并发的调用（首帧 + 第一次检查）等同一个
  Future<void>? _warmUpFuture;

  /// 正在跑的下载
  StreamSubscription<ApkDownloadProgress>? _sub;

  UpdateService get _service => ref.read(updateServiceProvider);

  UpdateAction _decide(UpdateInfo? remote) => decideUpdate(
        currentVersionCode: kAppVersionCode,
        remote: remote,
        promptedVersionCode: _prompted,
      );

  /// `prompt` 档要用的"已经弹过哪个版本"（进页面时从设置里读一次）
  int? _prompted;
}
