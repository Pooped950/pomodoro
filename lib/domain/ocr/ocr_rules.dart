import 'package:meta/meta.dart';

/// 课表识别的**可调规则**。
///
/// ## 为什么要做成"可覆盖"
///
/// 下面每个值都是**真图上一条条调出来的**（见各字段注释），换个学校 /
/// 换款 App 就得重调。以前调一次要发一个 APK —— 2026-10-08 用户要求：
/// 这类"参数"应该能**云端同步、免安装生效**。
///
/// 默认值原样留在代码里（离线 / 拉不到配置时照常用），
/// 远程 `remote_config.json` 里给什么就覆盖什么。
@immutable
class OcrRules {
  const OcrRules({
    this.roomKeywords = '楼室场馆房敦教',
    this.roomPrefix = '@',
    this.misreadAlways = '後',
    this.misreadBeforeDigit = '数敦',
    this.typoFixes = const <String, String>{'敦室': '教室'},
    this.roomSpanMinLen = 3,
    this.roomSpanMaxLen = 4,
    this.roomSpanMinHead = 4,
  });

  /// 教室行的**强规则**关键词。
  ///
  /// 校园课表的课程名几乎不含这些字（实测一整张课表一条都没有），
  /// 而教室行几乎总含其中一个 —— 连被换行截断的 `梧桐楼梧桐`（楼在行首）、
  /// 被认错字的 `梧桐洲四敦`（教→敦）都能兜住。
  final String roomKeywords;

  /// 教室行的**稳定前缀**。另一款 App 的教室写成 `@教2-213`，
  /// 课程名不会以它开头，拿来当判据最省事。
  final String roomPrefix;

  /// **单独出现**即可定性为误认的字（`後` = `楼` 之误；
  /// 简体课表里根本不会用「後」）。
  final String misreadAlways;

  /// **后面紧跟数字**才算误认的字（`数222` = `教222`、`北数-102` = `北教-102`）。
  /// 必须带数字：`数学分析` / `数据结构` 里也有这些字。
  final String misreadBeforeDigit;

  /// 整串替换（`敦室` → `教室`）。键是误认形态，值是正确形态。
  final Map<String, String> typoFixes;

  /// 「教室名跨行」时，被收进教室的碎片行长度下限 / 上限 / 课名剩余长度下限。
  ///
  /// 真图上 `东苑综合楼…` 会被 OCR 拆成 `东苑综` + `台楼…`，而 `东苑综`
  /// 单独看不出是教室。往上看一行：纯汉字、`[minLen, maxLen]` 字、
  /// 且课名还剩 ≥ [roomSpanMinHead] 字 → 也算教室。
  final int roomSpanMinLen;
  final int roomSpanMaxLen;
  final int roomSpanMinHead;

  static RegExp? _roomPatternCache;
  static OcrRules? _roomPatternFor;

  /// 教室行正则（带缓存，避免每次构建）
  RegExp get roomPattern {
    if (!identical(_roomPatternFor, this)) {
      final String kw = RegExp.escape(roomKeywords);
      final String px = RegExp.escape(roomPrefix);
      _roomPatternCache = RegExp(px.isEmpty ? '[$kw]' : '[$kw]|$px');
      _roomPatternFor = this;
    }
    return _roomPatternCache!;
  }

  /// 「误认字 + 数字」正则（`数222` / `北数-102` / `敦222`）
  RegExp get misreadDigitPattern =>
      RegExp('[${RegExp.escape(misreadBeforeDigit)}][^\\d]{0,2}\\d');

  /// 修正教室行里认错的字。
  ///
  /// ⚠️ [misreadBeforeDigit] 里的字只在**后面跟着数字**时才改：
  /// `数学` / `数据结构` / `伦敦` 里的这些字不能动。
  String fixTypos(String raw) {
    String s = raw;
    typoFixes.forEach((String from, String to) {
      if (from.isNotEmpty) s = s.replaceAll(from, to);
    });
    if (misreadBeforeDigit.isNotEmpty) {
      // 替换目标固定是 `教`：`数`/`敦` 都是 `教` 的形近误认（语义事实）
      s = s.replaceAll(
        RegExp('[${RegExp.escape(misreadBeforeDigit)}](?=[\\-\\s]?\\d)'),
        '教',
      );
    }
    return s;
  }

  /// 这一行里有没有"已知误认字"（投票修正的前置条件）
  bool hasMisreadChar(String line) {
    if (misreadAlways.isNotEmpty &&
        misreadAlways.split('').any((String c) => line.contains(c))) {
      return true;
    }
    if (misreadBeforeDigit.isNotEmpty &&
        misreadBeforeDigit.split('').any((String c) => line.contains(c))) {
      return true;
    }
    return false;
  }

  /// 从远程配置里的一项解析。字段缺失就用默认值（**局部覆盖**）。
  factory OcrRules.fromJson(Map<String, Object?> json) {
    const OcrRules d = OcrRules();

    String str(String key, String fallback) {
      final Object? v = json[key];
      return v is String && v.isNotEmpty ? v : fallback;
    }

    String optStr(String key, String fallback) =>
        json.containsKey(key) ? (json[key] as String? ?? '') : fallback;

    int num_(String key, int fallback) {
      final Object? v = json[key];
      return v is num ? v.toInt() : fallback;
    }

    Map<String, String> fixes = d.typoFixes;
    final Object? rawFixes = json['typoFixes'];
    if (rawFixes is Map) {
      final Map<String, String> m = <String, String>{};
      rawFixes.forEach((Object? k, Object? v) {
        if (k is String && v is String && k.isNotEmpty && v.isNotEmpty) {
          m[k] = v;
        }
      });
      if (m.isNotEmpty) fixes = m;
    }

    return OcrRules(
      roomKeywords: str('roomKeywords', d.roomKeywords),
      roomPrefix: optStr('roomPrefix', d.roomPrefix),
      misreadAlways: optStr('misreadAlways', d.misreadAlways),
      misreadBeforeDigit: optStr('misreadBeforeDigit', d.misreadBeforeDigit),
      typoFixes: fixes,
      roomSpanMinLen: num_('roomSpanMinLen', d.roomSpanMinLen),
      roomSpanMaxLen: num_('roomSpanMaxLen', d.roomSpanMaxLen),
      roomSpanMinHead: num_('roomSpanMinHead', d.roomSpanMinHead),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'roomKeywords': roomKeywords,
        'roomPrefix': roomPrefix,
        'misreadAlways': misreadAlways,
        'misreadBeforeDigit': misreadBeforeDigit,
        'typoFixes': typoFixes,
        'roomSpanMinLen': roomSpanMinLen,
        'roomSpanMaxLen': roomSpanMaxLen,
        'roomSpanMinHead': roomSpanMinHead,
      };
}

/// **当前生效**的规则。远程配置加载后整体替换（默认值 = 代码里的真图调优值）。
OcrRules ocrRules = const OcrRules();
