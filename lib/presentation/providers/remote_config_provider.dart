import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/remote_config_service.dart';
import '../../domain/remote/remote_config.dart';

/// 远程配置服务（`main.dart` 里 override 注入真实实现）
final remoteConfigServiceProvider = Provider<RemoteConfigService>(
  (Ref ref) => throw UnimplementedError('未注入 RemoteConfigService'),
);

/// 当前生效的远程配置。
///
/// 启动时先读本地缓存（离线也有得用），随后后台刷新一次；
/// 拿到新配置后 `state` 变化 → 整棵树重建 → 配色/文案立刻生效。
/// 课表规则走的是全局 [ocrRules]，导入时现取，同样立刻生效。
///
/// **任何失败都静默**：拉不到配置就用代码里的默认值，绝不能影响 App 使用。
class RemoteConfigNotifier extends Notifier<RemoteConfig?> {
  @override
  RemoteConfig? build() {
    unawaited(_boot());
    return null;
  }

  Future<void> _boot() async {
    try {
      final RemoteConfigService svc = ref.read(remoteConfigServiceProvider);
      final RemoteConfig? cached = await svc.warmUp();
      if (cached != null) state = cached;
      final RemoteConfig? fresh = await svc.check();
      if (fresh != null) state = fresh;
    } catch (_) {
      // 静默
    }
  }

  /// 手动强制刷新（「检查更新」时顺带调一次）
  Future<RemoteConfig?> refresh() async {
    try {
      final RemoteConfig? fresh =
          await ref.read(remoteConfigServiceProvider).check(force: true);
      if (fresh != null) state = fresh;
      return fresh;
    } catch (_) {
      return null;
    }
  }
}

final remoteConfigProvider =
    NotifierProvider<RemoteConfigNotifier, RemoteConfig?>(
  RemoteConfigNotifier.new,
);
