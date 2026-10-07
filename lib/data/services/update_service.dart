import 'dart:async';

import 'package:http/http.dart' as http;

import '../../domain/update/update_info.dart';
import '../repositories/settings_repository.dart';

/// Gitee 分发仓的 owner —— 用户注册后回填（Task 0 确认）。
///
/// 单测全部自己传 `endpoint`，不依赖这个值，所以它写错不会让测试变绿。
const String kGiteeOwner = 'pooped950';

/// 远端版本文件的地址（Gitee 公开仓的 raw 链接：国内直连、不需要登录/令牌）。
const String kUpdateEndpoint =
    'https://gitee.com/$kGiteeOwner/pomodoro-dist/raw/main/version.json';

/// 拿一段文本回来；失败返回 null（实现里不要抛给调用方）
typedef UpdateFetcher = Future<String?> Function(String url);

/// `UpdateService` 只需要存取三个字符串。
///
/// 抽成两方法的接口是为了**可测**：真 `SettingsRepository` 要 sqflite 数据库，
/// 宿主机单测跑不起来；生产代码用 [SettingsUpdateStore] 包一层即可。
abstract class UpdateStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// 把真设置表接进 [UpdateStore]
class SettingsUpdateStore implements UpdateStore {
  SettingsUpdateStore(this._settings);

  final SettingsRepository _settings;

  @override
  Future<String?> read(String key) => _settings.readString(key);

  @override
  Future<void> write(String key, String value) =>
      _settings.writeString(key, value);
}

/// 拉版本文件、缓存它、按节流决定要不要真的发请求。
///
/// 四条设计原则（都来自 spec §7.2 / §7.5）：
///   1. **静默失败**：任何异常都吞掉，只返回 null —— 检查更新绝不能影响 App 正常使用
///   2. **节流**：默认 10 分钟内只发一次（手动点「检查更新」用 `force: true` 绕过）
///   3. **缓存**：成功就把原文存起来，离线时还能显示"上次看到的最新版"
///   4. **绕 CDN**：请求带时间戳参数，否则 Gitee 的 CDN 可能长时间喂旧文件
class UpdateService {
  UpdateService({
    required this.store,
    UpdateFetcher? fetcher,
    this.endpoint = kUpdateEndpoint,
    this.minInterval = const Duration(minutes: 10),
    this.timeout = const Duration(seconds: 5),
  }) : _fetcher = fetcher ?? _httpFetcher;

  final UpdateStore store;
  final UpdateFetcher _fetcher;

  final String endpoint;
  final Duration minInterval;
  final Duration timeout;

  UpdateInfo? _cached;
  DateTime? _lastCheckAt;

  /// 上次成功解析出来的远端版本信息（内存里有；[warmUp] 之后也能从库里读回）
  UpdateInfo? get cached => _cached;

  /// 上次**发起检查**的时间（成功失败都算）
  DateTime? get lastCheckAt => _lastCheckAt;

  static Future<String?> _httpFetcher(String url) async {
    final http.Response res = await http.get(Uri.parse(url));
    return res.statusCode == 200 ? res.body : null;
  }

  /// 从设置里把上次的缓存读进内存。App 启动时调一次即可。
  Future<void> warmUp() async {
    try {
      final String? raw =
          await store.read(SettingsRepository.keyUpdateCachedJson);
      _cached = UpdateInfo.tryParse(raw);
      final String? at =
          await store.read(SettingsRepository.keyUpdateLastCheckAt);
      _lastCheckAt = at == null ? null : DateTime.tryParse(at);
    } catch (_) {
      // 读缓存失败也要能用（当作没有缓存）
    }
  }

  /// 检查一次。
  ///
  /// 返回**本次拉到并解析成功**的远端信息；失败 / 脏数据 / 被节流挡下都返回 null。
  /// 想显示"上次看到的最新版"请读 [cached]（失败不会冲掉它）。
  Future<UpdateInfo?> check({bool force = false}) async {
    if (!force && _isThrottled()) return null;

    final DateTime now = DateTime.now();
    try {
      final String? raw = await _fetcher(_urlWithCacheBuster(now)).timeout(timeout);
      await _recordCheck(now);

      final UpdateInfo? info = UpdateInfo.tryParse(raw);
      if (info == null) return null; // 脏数据：当作没拉到

      await store.write(SettingsRepository.keyUpdateCachedJson, raw!);
      _cached = info;
      return info;
    } catch (_) {
      // 网络炸了 / 超时 / 写库失败 —— 一律静默
      await _recordCheck(now);
      return null;
    }
  }

  /// 记下已弹过"更新说明"的版本（`prompt` 档只弹一次靠它）
  Future<void> markPrompted(int versionCode) async {
    try {
      await store.write(SettingsRepository.keyUpdatePromptedVersionCode,
          versionCode.toString());
    } catch (_) {
      // 记不上就下次再弹一次，不值得打扰用户
    }
  }

  /// 已经弹过的版本号；没记过返回 null
  Future<int?> promptedVersionCode() async {
    try {
      final String? raw =
          await store.read(SettingsRepository.keyUpdatePromptedVersionCode);
      return raw == null ? null : int.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  bool _isThrottled() {
    final DateTime? last = _lastCheckAt;
    if (last == null) return false;
    return DateTime.now().difference(last) < minInterval;
  }

  Future<void> _recordCheck(DateTime at) async {
    _lastCheckAt = at;
    try {
      await store.write(
          SettingsRepository.keyUpdateLastCheckAt, at.toIso8601String());
    } catch (_) {
      // 写不进去不影响本次结果
    }
  }

  /// 带时间戳，绕开 Gitee 的 CDN 缓存（Review Focus #1）
  String _urlWithCacheBuster(DateTime now) {
    final String sep = endpoint.contains('?') ? '&' : '?';
    return '$endpoint${sep}t=${now.millisecondsSinceEpoch}';
  }
}
