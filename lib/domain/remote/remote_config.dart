import 'dart:convert';

import 'package:meta/meta.dart';

import '../ocr/ocr_rules.dart';

/// 云端可调配置（`remote_config.json`）。
///
/// ## 为什么要有这个（2026-10-08 用户要求）
///
/// 「检查更新 → 下载 → **免安装**」。Flutter 的 Dart 代码是 AOT 编译进 APK 的，
/// **运行时换不了** —— 能免安装的只有**数据/参数**：
///
///   - **课表识别规则**（楼名词表、误认字映射、阈值）→ [ocr]
///   - **品牌主色** → [seedColorHex]
///   - **界面文案** → [strings]
///
/// 改这些只需推一份 JSON，App 拉下来立刻生效，不用发版。
/// 代码逻辑改动（底层重构、大版本）仍然要装 APK。
///
/// ## 局部覆盖
///
/// 所有字段都是**可选**的：远程给什么覆盖什么，没给的用代码里的默认值。
/// 解析失败 / 脏数据一律返回 null（当作没拉到，绝不半残地生效）。
@immutable
class RemoteConfig {
  const RemoteConfig({
    this.configVersion = 0,
    this.ocr = const OcrRules(),
    this.seedColorHex,
    this.strings = const <String, String>{},
  });

  /// 配置版本号（只用于显示 / 判断有没有变，不参与逻辑）
  final int configVersion;

  /// 课表识别的可调规则
  final OcrRules ocr;

  /// 品牌主色（`#RRGGBB` / `RRGGBB`）。null = 用代码里的番茄红。
  final String? seedColorHex;

  /// 界面文案覆盖表：**key = 代码里的原文**，value = 替换后的文案。
  ///
  /// 用原文当 key 是刻意的 —— 不用维护一套文案 ID，
  /// 以后想改哪句就把哪句包上 [t] 并在这里加一条。
  final Map<String, String> strings;

  /// 这份配置是不是"什么都没配"（解析出的空壳）
  bool get isEmpty =>
      configVersion == 0 && seedColorHex == null && strings.isEmpty;

  /// 解析。任何异常 / 非对象 都返回 null。
  static RemoteConfig? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      // 课表规则：允许 `ocr` 或 `timetable` 两种键名
      final Object? ocrRaw = decoded['ocr'] ?? decoded['timetable'];
      final OcrRules ocr = ocrRaw is Map
          ? OcrRules.fromJson(ocrRaw.cast<String, Object?>())
          : const OcrRules();

      final Map<String, String> strings = <String, String>{};
      final Object? sRaw = decoded['strings'];
      if (sRaw is Map) {
        sRaw.forEach((Object? k, Object? v) {
          if (k is String && v is String && k.isNotEmpty) strings[k] = v;
        });
      }

      final Object? seed = decoded['seedColor'];

      return RemoteConfig(
        configVersion: decoded['configVersion'] is num
            ? (decoded['configVersion']! as num).toInt()
            : 0,
        ocr: ocr,
        seedColorHex:
            seed is String && seed.trim().isNotEmpty ? seed.trim() : null,
        strings: strings,
      );
    } catch (_) {
      return null;
    }
  }
}

// ===========================================================================
// 全局生效值（远程配置加载后整体替换）
// ===========================================================================

/// 当前生效的文案覆盖表（原文 → 替换值）
Map<String, String> remoteStrings = const <String, String>{};

/// 当前生效的品牌主色（`#RRGGBB`）；null = 用代码里的番茄红
String? remoteSeedColorHex;

/// 把一份远程配置应用到全局（课表规则 / 文案 / 配色）。
///
/// 传 null 表示"拉不到配置" → 全部回到代码里的默认值。
void applyRemoteConfig(RemoteConfig? cfg) {
  ocrRules = cfg?.ocr ?? const OcrRules();
  remoteStrings = cfg?.strings ?? const <String, String>{};
  remoteSeedColorHex = cfg?.seedColorHex;
}

/// 取文案：远程配置里有同名覆盖就用覆盖值，否则用代码里的原文。
///
/// 用法：把要支持远程改的文案包一层 —— `Text(t('导入课表'))`。
String t(String original) => remoteStrings[original] ?? original;

/// 把 `#RRGGBB` / `RRGGBB` 解析成 Color 的 int；解析不了返回 null
int? parseHexColor(String? hex) {
  if (hex == null) return null;
  String s = hex.trim().replaceFirst('#', '');
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return null;
  final int? v = int.tryParse(s, radix: 16);
  return v;
}
