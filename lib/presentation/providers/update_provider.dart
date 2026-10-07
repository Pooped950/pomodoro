import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../core/app_info.dart';
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

  /// 有比当前更新的版本（小红点看它）
  bool get hasNewer =>
      remote != null && remote!.versionCode > kAppVersionCode;

  UpdateState copyWith({
    UpdateInfo? remote,
    DateTime? checkedAt,
    bool? checking,
    String? error,
    UpdateAction? action,
    bool clearError = false,
  }) =>
      UpdateState(
        remote: remote ?? this.remote,
        checkedAt: checkedAt ?? this.checkedAt,
        checking: checking ?? this.checking,
        error: clearError ? null : (error ?? this.error),
        action: action ?? this.action,
      );
}

/// 生产环境在 `main()` 里 override 成真实实例（和 settingsRepositoryProvider 同款）
final updateServiceProvider = Provider<UpdateService>(
  (Ref ref) => throw UnimplementedError(
    'updateServiceProvider 必须在 main() 里 override',
  ),
);

final updateStateProvider =
    NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);

/// 检查更新的状态机。
///
/// 为什么不用 FutureProvider：这里要**显式**区分"正在检查 / 成功 / 失败"，
/// 而且失败时还得保留上次的缓存 —— 用 Notifier 手写这三个状态最直白。
class UpdateNotifier extends Notifier<UpdateState> {
  @override
  UpdateState build() {
    // 先把上次成功的缓存显示出来（离线也能看到"上次看到的最新版"），
    // 不阻塞首帧：build 是同步的。
    unawaited(_refreshFromCache());
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
  Future<void> _collect({required UpdateInfo? fresh, required bool failed}) async {
    await _ensureWarmUp();
    if (!ref.mounted) return;
    state = UpdateState(
      remote: fresh ?? _service.cached,
      checkedAt: _service.lastCheckAt,
      checking: false,
      error: failed ? '检查失败，稍后再试' : null,
      action: _decide(fresh ?? _service.cached),
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

  /// 预热只跑一次：把 future 存下来，并发的调用（首帧 + 第一次检查）等同一个
  Future<void>? _warmUpFuture;

  UpdateService get _service => ref.read(updateServiceProvider);

  UpdateAction _decide(UpdateInfo? remote) => decideUpdate(
        currentVersionCode: kAppVersionCode,
        remote: remote,
        promptedVersionCode: _prompted,
      );

  /// `prompt` 档要用的"已经弹过哪个版本"（进页面时从设置里读一次）
  int? _prompted;
}
