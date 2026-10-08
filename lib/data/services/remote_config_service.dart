import 'dart:async';

import 'package:http/http.dart' as http;

import '../../domain/remote/remote_config.dart';
import '../repositories/settings_repository.dart';
import 'update_service.dart';

/// 远端**配置文件**的地址（和 `version.json` 同一个 Gitee 分发仓）。
///
/// 推一份 `remote_config.json` 上去，App 拉下来立刻生效 —— **不用发版**。
const String kConfigEndpoint =
    'https://gitee.com/$kGiteeOwner/$kGiteeRepo/raw/master/remote_config.json';

/// 拉远程配置、缓存它、按节流决定要不要真的发请求。
///
/// 设计原则和 [UpdateService] 完全一致（同一套踩坑经验）：
///   1. **静默失败**：任何异常都吞掉，只返回 null —— 拉配置绝不能影响 App 使用
///   2. **节流**：默认 30 分钟内只发一次（手动"检查更新"用 `force: true` 绕过）
///   3. **缓存**：成功就存原文，离线时继续用上次那份
///   4. **绕 CDN**：请求带时间戳，否则 Gitee 的 CDN 可能长时间喂旧文件
class RemoteConfigService {
  RemoteConfigService({
    required this.store,
    UpdateFetcher? fetcher,
    this.endpoint = kConfigEndpoint,
    this.minInterval = const Duration(minutes: 30),
    this.timeout = const Duration(seconds: 5),
  }) : _fetcher = fetcher ?? _httpFetcher;

  final UpdateStore store;
  final UpdateFetcher _fetcher;

  final String endpoint;
  final Duration minInterval;
  final Duration timeout;

  RemoteConfig? _cached;
  DateTime? _lastCheckAt;

  /// 当前生效的配置（内存里有；[warmUp] 之后也能从库里读回）
  RemoteConfig? get cached => _cached;

  DateTime? get lastCheckAt => _lastCheckAt;

  static Future<String?> _httpFetcher(String url) async {
    final http.Response res = await http.get(Uri.parse(url));
    return res.statusCode == 200 ? res.body : null;
  }

  /// 从设置里把上次的缓存读回内存并应用。App 启动时调一次即可。
  ///
  /// ⚠️ 用 `??=`：预热是异步的，可能和一次刚落地的 [check] 赛跑 ——
  /// 内存里已经有更新的配置时，不能被库里那份旧的覆盖回去。
  Future<RemoteConfig?> warmUp() async {
    try {
      final String? raw = await store.read(SettingsRepository.keyRemoteConfig);
      _cached ??= RemoteConfig.tryParse(raw);
      final String? at =
          await store.read(SettingsRepository.keyRemoteConfigAt);
      _lastCheckAt ??= at == null ? null : DateTime.tryParse(at);
    } catch (_) {
      // 读缓存失败也要能用（当作没有缓存）
    }
    applyRemoteConfig(_cached);
    return _cached;
  }

  /// 检查一次。成功拉到就**立即应用到全局**。
  ///
  /// 返回本次拉到并解析成功的配置；失败 / 脏数据 / 被节流挡下都返回 null。
  Future<RemoteConfig?> check({bool force = false}) async {
    if (!force && _isThrottled()) return null;

    final DateTime now = DateTime.now();
    try {
      final String? raw =
          await _fetcher(_urlWithCacheBuster(now)).timeout(timeout);
      await _recordCheck(now);

      final RemoteConfig? cfg = RemoteConfig.tryParse(raw);
      if (cfg == null) return null; // 脏数据：当作没拉到

      await store.write(SettingsRepository.keyRemoteConfig, raw!);
      _cached = cfg;
      applyRemoteConfig(cfg);
      return cfg;
    } catch (_) {
      // 网络炸了 / 超时 / 写库失败 —— 一律静默
      await _recordCheck(now);
      return null;
    }
  }

  bool get isThrottled => _isThrottled();

  bool _isThrottled() {
    final DateTime? last = _lastCheckAt;
    if (last == null) return false;
    return DateTime.now().difference(last) < minInterval;
  }

  Future<void> _recordCheck(DateTime at) async {
    _lastCheckAt = at;
    try {
      await store.write(
          SettingsRepository.keyRemoteConfigAt, at.toIso8601String());
    } catch (_) {
      // 写不进去不影响本次结果
    }
  }

  /// 带时间戳，绕开 Gitee 的 CDN 缓存
  String _urlWithCacheBuster(DateTime now) {
    final String sep = endpoint.contains('?') ? '&' : '?';
    return '$endpoint${sep}t=${now.millisecondsSinceEpoch}';
  }
}
