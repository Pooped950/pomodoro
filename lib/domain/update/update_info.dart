import 'dart:convert';

import 'package:meta/meta.dart';

/// 允许下载 APK 的**域名白名单**（含子域）。
///
/// 为什么必须有：`version.json` 放在公开仓库里，万一它被改坏、或被塞进一个恶意地址，
/// App 也绝不能去下载任意来源的安装包 —— 这条链路的尽头是"装一个 APK"。
/// 以后有自己的域名，往这里加一条即可。
const List<String> kAllowedApkHosts = <String>['gitee.com'];

/// 更新提示的档位 —— 由**远端** `version.json` 的 `policy` 字段控制，改一个字段即生效。
enum UpdatePolicy {
  /// 只显示"有新版本"的小红点，不弹窗（日常默认）
  silent,

  /// 下次启动弹一次；可「以后再说」，同一个版本只弹一次
  prompt,

  /// 弹窗不可关，只能「立即更新」或退出
  force,
}

/// 远端版本信息（`version.json` 的解析结果）。
@immutable
class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.sha256,
    required this.sizeBytes,
    this.publishedAt,
    this.notes = const <String>[],
    this.policy = UpdatePolicy.silent,
    this.downloadPage,
  });

  /// 版本比较的**唯一依据**（对应 pubspec 的 `+N`）
  final int versionCode;

  /// 只用于显示
  final String versionName;

  final String apkUrl;

  /// 下载后校验用（64 位十六进制，小写）
  final String sha256;

  /// 下载前查磁盘空间、界面上显示体积
  final int sizeBytes;

  final DateTime? publishedAt;

  /// 给用户看的更新说明（纯文本展示）
  final List<String> notes;

  final UpdatePolicy policy;

  /// 「打开发布页」按钮的目标
  final String? downloadPage;

  /// 容错解析：**必填字段**任何一个不合法就返回 null（调用方当成"没有版本信息"）。
  ///
  /// 宁可"当作没有新版"，也不要拿半条脏数据去走下载安装 —— 这条链路尽头是装包。
  static UpdateInfo? tryParse(String? raw) {
    if (raw == null) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    final Object? code = decoded['versionCode'];
    if (code is! int || code <= 0) return null;

    final Object? name = decoded['versionName'];
    if (name is! String || name.trim().isEmpty) return null;

    final Object? size = decoded['sizeBytes'];
    if (size is! int || size <= 0) return null;

    final Object? sha = decoded['sha256'];
    if (sha is! String || !_isSha256(sha)) return null;

    final Object? url = decoded['apkUrl'];
    if (url is! String || !isAllowedApkUrl(url)) return null;

    return UpdateInfo(
      versionCode: code,
      versionName: name.trim(),
      apkUrl: url,
      sha256: sha.toLowerCase(),
      sizeBytes: size,
      publishedAt: _parseDate(decoded['publishedAt']),
      notes: _parseNotes(decoded['notes']),
      policy: _parsePolicy(decoded['policy']),
      downloadPage: _parseLink(decoded['downloadPage']),
    );
  }

  /// 只放行 **https + 白名单域名**（恰好等于白名单，或是它的子域）。
  static bool isAllowedApkUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    final String host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    for (final String allowed in kAllowedApkHosts) {
      if (host == allowed || host.endsWith('.$allowed')) return true;
    }
    return false;
  }

  static bool _isSha256(String s) =>
      s.length == 64 && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(s);

  /// 脏日期 → null（界面上就不显示时间，绝不抛异常、也不显示 "null"）
  static DateTime? _parseDate(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  static List<String> _parseNotes(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .whereType<String>()
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
  }

  /// 认不出的档位退回 [UpdatePolicy.silent]：宁可少弹，不要错弹
  static UpdatePolicy _parsePolicy(Object? value) {
    switch (value) {
      case 'prompt':
        return UpdatePolicy.prompt;
      case 'force':
        return UpdatePolicy.force;
      default:
        return UpdatePolicy.silent;
    }
  }

  static String? _parseLink(Object? value) {
    if (value is! String) return null;
    final Uri? uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return value;
  }
}
