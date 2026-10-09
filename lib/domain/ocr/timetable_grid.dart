/// 课表版面解析 —— 从 OCR 文本行 + 拼图像素还原「星期 × 节次」网格。
///
/// ## 两层分工（2026-10-07 定稿）
///
///   - **几何来自像素**：课程块的第几列、第几节到第几节，量自拼图里的
///     色块和节次栏（`timetable_geometry.dart`）。理由：课程块是
///     「文字挤在块顶、下面大片留白」，光看文字 y 推不出真实跨度；
///     相邻两块的缝隙可以只有 2px，纯文字间距也聚不到一起。
///   - **文字来自 OCR**：课名、教室，按格归属后拆「课名行 / 教室行」，
///     再拿词表修正认错的字（`timetable_vocab.dart`）。
///
/// 传了 `pixels` 走像素路线（真机导入永远走这条）；传不了（测试、
/// 异常兜底）退回纯文字路线 —— 旧的间距聚格逻辑保留在那条路上。
///
/// ## 输入长什么样（真实样本的观察结论，2026-10-06/07）
///
/// - 顶部：时间 / 标题 / 学期 / 周次下拉（表头以上，直接丢弃）
/// - **星期表头行**：`周一` `周二`…（⚠️ 行首可能粘着表格竖线 `|周二`；
///   OCR 会把相邻两列并成一行 `周三 周四`）
/// - 左侧节次栏：孤立的 `1` `2` `3`…（⚠️ `13` 会被读残成 `1`，
///   甚至整块漏读 —— 见 [_recoverAnchors]）
/// - 课程格：一个块 = 课名行 + 教室行挤在块顶
/// - **跨列合并行**：OCR 把同一横排上相邻几列的文字粘成一条长线
///   （`结构力学量子光学材料力学工程制图`），有的还留有空格痕迹
///   （`307敦室 A (一)`）—— 见 [_splitSpanningLine]
/// - 噪声：底部导航、悬浮球数字、悬浮箭头（像素层已排除）
library;

import 'dart:typed_data';

import 'common_courses.dart';
import 'ocr_result.dart';
import 'ocr_rules.dart';
import 'timetable_geometry.dart';
import 'timetable_vocab.dart';


/// 一列 = 一个星期。列宽边界用于把任意文本行归到"最可能属于哪一列"。
class WeekdayColumn {
  const WeekdayColumn({
    required this.weekday,
    required this.centerX,
    required this.left,
    required this.right,
    this.date,
  });

  /// 1 = 周一 … 7 = 周日
  final int weekday;
  final double centerX;

  /// 归列边界（相邻两列中心的垂直平分线；首尾外扩半列距）
  final double left;
  final double right;

  /// 表头下方的日期（如 10-14），识别不出为 null
  final String? date;
}

/// 一个课程格：同一列里的一块课（几何范围 + 归属到它的文本行）。
class ParsedCell {
  const ParsedCell({
    required this.weekday,
    required this.top,
    required this.bottom,
    required this.lines,
    required this.spanningSuspicion,
    this.startPeriod,
    this.endPeriod,
    this.name,
    this.location,
  });

  /// 1 = 周一 … 7 = 周日
  final int weekday;
  final double top;
  final double bottom;

  /// 格内的原始文本行（已按 y 排序、已剥行首竖线）
  final List<String> lines;

  /// 格的节次范围（由左侧节次栏反推；截图里没有节次栏时为 null）
  final int? startPeriod;
  final int? endPeriod;

  /// 课名（像素路线里拆好的）；纯文字路线为 null，走 [courseNameGuess]
  final String? name;

  /// 教室（同上）
  final String? location;

  /// 疑似 OCR 事故（课名空了或没有汉字），预览时让用户重点改
  final bool spanningSuspicion;

  /// 课程名猜测。像素路线 = 拆好的 [name]；文字路线 = 第一行非空文本
  String get courseNameGuess {
    final String? n = name;
    if (n != null) return n;
    for (final String line in lines) {
      final String t = cleanOcrLine(line);
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  /// 地点猜测。像素路线 = 拆好的 [location]；文字路线 = 含教室字样的最后一行
  String get locationGuess {
    final String? l = location;
    if (l != null) return l;
    for (final String line in lines.reversed) {
      final RegExpMatch? m =
          RegExp(r'[|]?([^\s|]*(?:教室|楼|场|馆)[^\s|]*)').firstMatch(line);
      if (m != null) return m.group(1)!;
    }
    return '';
  }

  String get rawText => lines.join('\n');
}

/// 解析结果：网格 + 被丢掉的内容（预览页可以展示"为什么这行没进课表"）。
class ParsedTimetable {
  const ParsedTimetable({
    required this.columns,
    required this.cells,
    this.periodAnchors = const <PeriodAnchor>[],
    this.navDropped = const <String>[],
  });

  final List<WeekdayColumn> columns;
  final List<ParsedCell> cells;

  /// 左侧节次栏每节课的纵向位置（按节次升序）。
  ///
  /// 暴露出来是给**导入流程**用的：用户填"上午最后一节几点结束"和"下午第一节
  /// 几点开始"，但 App 还得知道**上午有几节**才能把时间排下去。
  ///
  /// 截图里没有节次栏时为空。
  final List<PeriodAnchor> periodAnchors;

  /// 被当成导航/噪声丢弃的文本行
  final List<String> navDropped;
}

/// 节次栏里某一节的纵向位置
class PeriodAnchor {
  const PeriodAnchor({required this.period, required this.centerY});

  /// 节次序号，从 1 开始
  final int period;

  /// 这一节在截图里的纵向中心（像素）
  final double centerY;
}

class TimetableParseException implements Exception {
  const TimetableParseException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 星期表头能匹配到的列数下限 —— 低于它基本不是课表截图
const int kMinWeekdayColumns = 2;

/// 「周X」在**行首**（剥掉行首噪声之后）
final RegExp _weekdayLeadPattern = RegExp(r'^周\s?[一二三四五六日天]');

/// 「周X」出现在任意位置 —— 一行里可能有多个（OCR 会把相邻两列并成一行）。
/// 中间那个空格可有可无：`周三 周四` 和 `周三周四` 都见过。
final RegExp _weekdayAnyPattern = RegExp(r'周\s?([一二三四五六日天])');

/// 剥掉 OCR 粘在行首的装饰噪声。
///
/// ## 为什么必须有这一步（2026-10-07 真实样本踩到）
///
/// 校园课表 App 的表格竖线会被识别成一个竖线字符，粘在文本前面：
/// 表头那行拿到的是 `|周二` 而不是 `周二`。原来的正则锚定 `^周X`，
/// 于是**整整一列匹配失败、凭空消失** —— 连锁反应是：
///   1. 周二缺位 → 周一列的归列边界被撑成两倍宽 → 左侧节次栏的
///      `1 2 3…` 落进了"课程区"、被当噪声丢掉 → 节次锚点 0 个
///      → 节次时间表排不出来 → 周视图只剩一行，课程全挤在最上面
///   2. 周二的内容按"最近的列"兜底，全被塞进最右边的**周日** → 周日凭空多出课
///
/// 所以只剥**行首**、只剥竖线类字符和空白，不碰正文。
String _stripLeadNoise(String raw) =>
    raw.trim().replaceFirst(RegExp(r'^[|丨│｜\s]+'), '');

/// 空白（含全角空格）
final RegExp _spacePattern = RegExp(r'\s');

/// [s] 的前 [index] 个字符里有几个**非空白**字符。
///
/// 把「带空格的原文位置」换算成「按字宽均分的位置」，见表头 x 区间的算法。
int _denseIndex(String s, int index) {
  int n = 0;
  for (int i = 0; i < index && i < s.length; i++) {
    if (!_spacePattern.hasMatch(s[i])) n++;
  }
  return n;
}

/// 这一行像不像「星期表头」：剥掉行首噪声后必须以 `周X` 开头
/// 这个 token 是**带结构的**日期（`10/9`、`10月9日`、`2026-10-09`），
/// 而不是光秃秃的日号（`9`）。
///
/// 用途：区分「课程区里的裸数字」和「节次栏的裸数字」——
/// 前者可能是日期行被拆散的碎片，后者是节次号，要排除。
bool _hasDateStructure(String raw) {
  final String s = _stripLeadNoise(raw).replaceAll(RegExp(r'\s+'), '');
  return s.contains('/') ||
      s.contains('-') ||
      s.contains('.') ||
      s.contains('月') ||
      s.contains('日') ||
      s.contains('号') ||
      RegExp(r'^\d{4}').hasMatch(s);
}

/// 「这一行像不像一个日期」—— 表头下方那一排日期的**写法极其不统一**。
///
/// ## 为什么要认这么多写法（2026-10-09 用户明确要求）
///
/// 同一个日期在不同 App / 学校 / 手抄里能写出十几种样子：
///
/// | 形态 | 例子 |
/// |---|---|
/// | 数字 + 各种分隔符 | `10/9`、`10-9`、`10.9`、`10、9`、`10\9` |
/// | 中文月日 | `10月9日`、`10月9号`、`10月09日` |
/// | 中文数字 | `10月九日`、`九月九号`、`九月九日` |
/// | 只写日号 | `9`、`09`、`9日`、`9号`、`九日` |
/// | 完整日期 | `2026-10-09`、`2026/10/9` |
///
/// **只认其中一种的代价**（2026-10-09 真机实测踩到）：表头下方那排日期
/// 整排提不到 → 裸表头兜底失去"位置来源" → 一旦 ML Kit 漏读「一」「二」
/// （细横线字形，实测必漏），就只认出 5 列、**周一周二的课全丢**，
/// 13 门课只剩 7 格。
///
/// ## 显式排除「第 6 周」「第 1 节」
///
/// 它们长得也像数字，但一个是**周次**、一个是**节次**，混进日期行会把列距算歪。
///
/// ## ⚠️ 纯数字很宽松，调用方必须限定区域
///
/// `^\d{1,2}$` 连节次号都匹配。所以这个函数只回答"**长得像不像日期**"，
/// 是否真是日期由调用方的位置条件决定（表头正下方那一条带）。
bool looksLikeDateToken(String raw) {
  final String s = _stripLeadNoise(raw).replaceAll(RegExp(r'\s+'), '');
  if (s.isEmpty || s.length > 12) return false;

  // 不是日期的东西：周次 / 节次
  if (RegExp(r'^第\s*\d{1,2}\s*[周週]$').hasMatch(s)) return false;
  if (RegExp(r'^第\s*\d{1,2}\s*节$').hasMatch(s)) return false;

  // 完整日期：2026-10-09 / 2026/10/9 / 2026.10.9
  if (RegExp(r'^\d{4}\s*[-/.]\s*\d{1,2}\s*[-/.]\s*\d{1,2}$').hasMatch(s)) {
    return true;
  }

  // 数字 + 分隔符：10/9、10-9、10.9、10、9、10\9
  if (RegExp(r'^\d{1,2}\s*[-/.、,，\\]\s*\d{1,2}$').hasMatch(s)) return true;

  // 中文月日：10月9日 / 10月9号 / 10月九日 / 九月九号
  if (RegExp(r'^\d{1,2}\s*月\s*(\d{1,2}|[一二三四五六七八九十]{1,3})\s*[日号]?$')
      .hasMatch(s)) {
    return true;
  }
  if (RegExp(r'^[一二三四五六七八九十]{1,3}\s*月\s*'
          r'[一二三四五六七八九十]{1,3}\s*[日号]?$')
      .hasMatch(s)) {
    return true;
  }

  // 只写日号：9 / 09 / 9日 / 9号 / 九 / 九日
  if (RegExp(r'^\d{1,2}\s*[日号]?$').hasMatch(s)) return true;
  if (RegExp(r'^[一二三四五六七八九十]{1,3}\s*[日号]?$').hasMatch(s)) {
    return true;
  }

  return false;
}

/// 「这一行像不像一个节次」—— 节次栏的写法同样不统一。
///
/// 认：`1`、`01`、`第1节`、`1节`、`一`、`十二`、`第十三节`
///
/// 不认：`08:00`（时刻）、`第6周`（周次）、`10月9日`（日期）。
///
/// 返回节次号；认不出返回 null。
int? parsePeriodToken(String raw) {
  final String s = _stripLeadNoise(raw).replaceAll(RegExp(r'\s+'), '');
  if (s.isEmpty || s.length > 8) return null;

  // 阿拉伯数字（可带「第…节」外壳）
  final RegExpMatch? arabic =
      RegExp(r'^(?:第)?\s*(\d{1,2})\s*(?:节)?$').firstMatch(s);
  if (arabic != null) {
    final int? p = int.tryParse(arabic.group(1)!);
    return (p != null && p >= 1 && p <= 30) ? p : null;
  }

  // 中文数字：一、十二、二十三（可带「第…节」外壳）
  final RegExpMatch? chinese =
      RegExp(r'^(?:第)?\s*([一二三四五六七八九十]{1,3})\s*(?:节)?$').firstMatch(s);
  if (chinese != null) {
    final int? p = _chineseNumber(chinese.group(1)!);
    return (p != null && p >= 1 && p <= 30) ? p : null;
  }

  return null;
}

/// 中文数字 → int（只处理 1~30 这个量级，够节次用）。
///
/// 规则：`十` = 10、`十二` = 12、`二十` = 20、`二十三` = 23、`三十` = 30。
int? _chineseNumber(String s) {
  const Map<String, int> digit = <String, int>{
    '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
    '六': 6, '七': 7, '八': 8, '九': 9,
  };
  if (s.isEmpty) return null;
  if (!s.contains('十')) {
    // 单个数字，或者多字但都是数字（如「二三」—— 不算合法数字，返回 null）
    return s.length == 1 ? digit[s] : null;
  }
  final int idx = s.indexOf('十');
  final String head = s.substring(0, idx);
  final String tail = s.substring(idx + 1);
  final int tens = head.isEmpty ? 1 : (digit[head] ?? 0);
  final int ones = tail.isEmpty ? 0 : (digit[tail] ?? 0);
  if (tens == 0) return null;
  return tens * 10 + ones;
}

bool _looksLikeWeekdayHeader(String raw) =>
    _weekdayLeadPattern.hasMatch(_stripLeadNoise(raw));

/// 行首的「上课时刻」：`08:00-08:50` / `08:00~08:50`，全角冒号也认。
final RegExp _leadClockPattern =
    RegExp(r'^\s*\d{1,2}\s*[:：]\s*\d{2}\s*[-~—－]\s*\d{1,2}\s*[:：]\s*\d{2}\s*');
/// 剥掉行首的上课时刻（没有就原样返回）。
String _stripLeadClock(String s) => s.replaceFirst(_leadClockPattern, '');

/// 一段文字的**显示宽度**：汉字/全角算 1，其余（数字、冒号、连字符）算半宽。
///
/// 用来把「行首时刻」折算成 x 偏移。⚠️ 不能按字符数比例算：
/// 时刻里全是窄字符，按字符算会把偏移估大一倍 —— 实测
/// `10:10-11:00 层次) 语-读`（框 x=20..334）按字符算偏移 203px、
/// 按宽度算 164px，而真实内容是从约 170px 开始的。
double _wideUnits(String s) {
  double u = 0;
  for (final int r in s.runes) {
    u += r >= 0x2E80 ? 1.0 : 0.5;
  }
  return u;
}

/// 解析入口。规则见文件头注释。
///
/// [pixels] 是拼图的原始像素（RGBA），能传就走**像素路线**：
/// 课程块的行列范围量自色块本身，比文字坐标可信得多。
ParsedTimetable parseTimetable(
  List<OcrBlock> blocks, {
  TimetablePixels? pixels,
}) {
  if (blocks.length < kMinWeekdayColumns) {
    throw const TimetableParseException('识别内容太少，不像一张课表截图');
  }

  final List<OcrBlock> sorted = List<OcrBlock>.of(blocks)
    ..sort((OcrBlock a, OcrBlock b) => a.top.compareTo(b.top));

  // 块高与最大 y —— 表头扫描、锚点恢复、像素几何都要用，提到最前面只算一次
  final double maxY = sorted
      .map((OcrBlock b) => b.bottom)
      .reduce((double a, double b) => a > b ? a : b);
  final List<double> heights =
      sorted.map((OcrBlock b) => b.height).toList()..sort();
  final double medianHeight = heights[heights.length ~/ 2];

  // ---- 1. 星期表头行：以「周X」开头的行（可能多行、可能合并） ----
  final List<_HeaderPart> headerParts = <_HeaderPart>[];
  for (final OcrBlock b in sorted) {
    if (!_looksLikeWeekdayHeader(b.text)) continue;

    // 先剥行首噪声，后面的字符位置才和 x 对得上
    final String cleaned = _stripLeadNoise(b.text);
    if (cleaned.isEmpty) continue;

    // 一行里可能有多个「周X」（OCR 会把相邻两列并成一行），而且**中间不一定
    // 有空格**（`周三 周四` 和 `周三周四` 都见过）。所以不按空格拆，而是找出
    // 每个「周X」的**字符位置**，再按字符位置占整行的比例折算成 x 区间。
    //
    // ⚠️ 折算时**空白不占字宽**（先把空白剔掉再按剩余字符数均分）。
    // 汉字在等宽栅格里基本同宽，而空格比汉字窄得多 —— 让空格也占一个字宽，
    // 后面那半边的中心会往左偏小半格，列边界跟着偏。
    final String dense = cleaned.replaceAll(_spacePattern, '');
    if (dense.isEmpty) continue;

    final List<RegExpMatch> hits =
        _weekdayAnyPattern.allMatches(cleaned).toList();
    for (final RegExpMatch hit in hits) {
      final int start = _denseIndex(cleaned, hit.start);
      final int length =
          hit.group(0)!.replaceAll(_spacePattern, '').length;
      headerParts.add(_HeaderPart(
        weekday: _weekdayNumber(hit.group(1)!),
        left: b.left + b.width * (start / dense.length),
        right: b.left + b.width * ((start + length) / dense.length),
        top: b.top,
        bottom: b.bottom,
      ));
    }
  }
  // 同一个星期取第一次出现（重复说明表头被识别了两次）
  final Map<int, _HeaderPart> byWeekday = <int, _HeaderPart>{};
  for (final _HeaderPart h in headerParts) {
    byWeekday.putIfAbsent(h.weekday, () => h);
  }
  if (byWeekday.length < kMinWeekdayColumns) {
    // ---- 1b. 裸表头兜底（2026-10-07 新增，另一款校园 App 实测）----
    //
    // 有些 App 的表头写的是**裸的「一 二 三 四 五 六 日」**（没有「周」字），
    // 上面的 `^周X` 锚定一个都匹配不上。更糟的是 ML Kit 会把「一」「二」
    // **整块漏读**（细横线字形），只认得出 `三四`（还粘成一行）、`五`、`六`、`日m`。
    //
    // 所以拿**日期行**（`11/2 11/3 …`，7 个都在、间距就是列距）当位置来源，
    // 拿认得出的那几个标签当**身份锚点**，两边一配就把 7 列补齐。
    final _BareHeaderScan? bare =
        _bareHeaderScan(sorted, maxY, medianHeight);
    if (bare != null) {
      for (final _HeaderPart h in bare.columns) {
        byWeekday.putIfAbsent(h.weekday, () => h);
      }
      // ⚠️ 只把**真正的表头标签**加进 headerParts —— 日期行推导出来的那些
      // 带的是日期行的上下沿，加进来会把"表头以上不算网格"这条判断往下挪。
      headerParts.addAll(bare.labelParts);
    }
  }
  if (byWeekday.length < kMinWeekdayColumns) {
    throw const TimetableParseException('没找到星期表头（周一～周日），'
        '请确认截图中课表网格完整可见');
  }
  final List<int> weekdays = byWeekday.keys.toList()..sort();
  final List<WeekdayColumn> columns = <WeekdayColumn>[];
  for (int i = 0; i < weekdays.length; i++) {
    final _HeaderPart h = byWeekday[weekdays[i]]!;
    columns.add(WeekdayColumn(
      weekday: h.weekday,
      centerX: (h.left + h.right) / 2,
      left: 0,
      right: 0,
    ));
  }
  // 列边界：相邻中心的**严格中点**（不用各自半间距 —— 列距稍有不等时，
  // 两种算法的边界会差出零点几像素、相邻列的范围互相重叠，
  // 压线的字就归错列；中点法保证相邻列无缝、无重叠）
  for (int i = 0; i < columns.length; i++) {
    final double left = i == 0
        ? columns[i].centerX -
            ((i + 1 < columns.length
                    ? columns[i + 1].centerX - columns[i].centerX
                    : 100) /
                2)
        : (columns[i - 1].centerX + columns[i].centerX) / 2;
    final double right = i + 1 == columns.length
        ? columns[i].centerX +
            ((i > 0
                    ? columns[i].centerX - columns[i - 1].centerX
                    : 100) /
                2)
        : (columns[i].centerX + columns[i + 1].centerX) / 2;
    columns[i] = WeekdayColumn(
      weekday: columns[i].weekday,
      centerX: columns[i].centerX,
      left: left,
      right: right,
    );
  }

  final double headerBottom = headerParts
      .map((_HeaderPart h) => h.bottom)
      .reduce((double a, double b) => a > b ? a : b);
  // 表头 y 带的上沿。表头**以上**的内容（时间/标题/学期/周次下拉）不属于网格，
  // 全部丢弃 —— 否则它们会被按中心归进某几列，变成凭空的课程格。
  final double headerTop = headerParts
      .map((_HeaderPart h) => h.top)
      .reduce((double a, double b) => a < b ? a : b);

  // ---- 2. 日期行：表头正下方那一排日期 ----
  //
  // ⚠️ 斜杠也要认（2026-10-07 真机实测）：另一款 App 写的是 `11/2`，
  // 只认 `-` 的话这一整行既进不了列、也定不出 `dateRowBottom`，
  // 后果是**日期文本被当成课程内容塞进格子里**（课名变成 `11/4材料力学A()上`）。
  //
  // ⚠️ 还要认**光秃秃的日号**（2026-10-08 真机实测）：这个 App 的日期行
  // 写的是 `5` `6` `7` …（不带月份），一个都不匹配 → `dateRowBottom`
  // 停在表头下沿 → 日期被当成课程内容，课名变成 `5材料力`、`7材料力学`。
  //
  // ⚠️ 判据**统一走全局的 [looksLikeDateToken]**（2026-10-09）：以前这里和
  // `_bareHeaderScan` 各写一份，改一处漏一处 —— 真机上就是"主流程认纯日号、
  // 兜底不认"，导致兜底失效、周一周二的课全丢。现在只有一份实现。
  double dateRowBottom = headerBottom;
  for (final OcrBlock b in sorted) {
    if (b.top < headerBottom || b.top > headerBottom + 80) continue;
    final List<String> tokens = b.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((String s) => s.isNotEmpty)
        .toList();
    if (tokens.isEmpty || !tokens.every(looksLikeDateToken)) continue;
    // 光秃秃的日号只认**课程区**里的（节次栏的 `1`/`2` 也是裸数字，
    // 虽然它在表头下面，但那是节次号不是日期）
    if (!tokens.any(_hasDateStructure) &&
        b.centerX < columns.first.left) {
      continue;
    }
    final double slot = b.width / tokens.length;
    for (int i = 0; i < tokens.length; i++) {
      final double tokenCx = b.left + slot * (i + 0.5);
      for (int c = 0; c < columns.length; c++) {
        if (tokenCx >= columns[c].left && tokenCx < columns[c].right) {
          columns[c] = WeekdayColumn(
            weekday: columns[c].weekday,
            centerX: columns[c].centerX,
            left: columns[c].left,
            right: columns[c].right,
            date: tokens[i],
          );
          break;
        }
      }
    }
    dateRowBottom = b.bottom > dateRowBottom ? b.bottom : dateRowBottom;
  }

  // ---- 3. 节次锚点（增强版：漏读补位 + 读残收编，见函数注释） ----
  final List<PeriodAnchor> anchors =
      _recoverAnchors(sorted, columns.first.left, dateRowBottom);

  // ---- 4. 分流：像素路线 / 纯文字路线 ----
  if (pixels != null) {
    final TimetableGeometry? rawGeometry = TimetableGeometryScanner.analyze(
      width: pixels.width,
      height: pixels.height,
      rgba: pixels.rgba,
      bands: <GeometryBand>[
        for (final WeekdayColumn c in columns)
          GeometryBand(left: c.left, right: c.right),
      ],
      gutterRight: columns.first.left,
      yTop: dateRowBottom + 2,
      yBottom: maxY - medianHeight * 1.2,
    );
    // 像素扫描会在表头/日期行附近**多认出一行**，也会把课程文字的左边缘
    // 误当节次行、把真节次行粘连后丢掉（详见 snapToAnchors 的注释）。
    // OCR 的节次栏是印在图上的数字，按它校正。
    final TimetableGeometry? geometry = rawGeometry?.snapToAnchors(
      anchors.map((PeriodAnchor a) => a.centerY).toList(),
    );
    // 像素量出的节次行必须和 OCR 认出的节次栏对得上，才可信：
    // 每个 OCR 锚点附近都应该有一个像素标签。对不上说明这张图的
    // 配色/版面出乎意料，退回纯文字路线更稳。
    if (geometry != null &&
        _geometryAgreesWithAnchors(geometry, anchors)) {
      return _parseWithGeometry(
        sorted: sorted,
        columns: columns,
        anchors: anchors,
        geometry: geometry,
        headerTop: headerTop,
        headerBottom: headerBottom,
        dateRowBottom: dateRowBottom,
        maxY: maxY,
        medianHeight: medianHeight,
      );
    }
  }

  return _parseTextOnly(
    sorted: sorted,
    columns: columns,
    anchors: anchors,
    headerTop: headerTop,
    headerBottom: headerBottom,
    dateRowBottom: dateRowBottom,
    maxY: maxY,
    medianHeight: medianHeight,
    firstColumnLeft: columns.first.left,
  );
}

/// 拼图的原始像素（RGBA，4 字节/像素），像素路线的输入。
class TimetablePixels {
  const TimetablePixels({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;
}

// ===========================================================================
// 节次锚点：漏读补位 + 读残收编
// ===========================================================================

/// 从节次栏的孤立数字块恢复完整的节次锚点表。
///
/// ## 真实样本的两个坑（2026-10-07）
///
///   - 第 7 节的标签被 ML Kit **整块漏读**（不是读残，是压根没有这个块）
///   - 第 13 节的 `13` 被读成 `1`，且因为"节次号必须递增"被旧逻辑丢掉
///
/// 后果：13 节的课表只认出 11 个锚点，第 7 节之后的所有课全部错位一格，
/// 排时间的时候课间被挤成 0（用户报的"课间没做出来"就是这么来的）。
///
/// ## 修法：位置是可信的，数字不一定
///
/// 1. 按 y 排序后逐个收编：节次号递增的直接要；**不递增但 y 正好落在
///    下一节的位置上**的也收编（按位置重新编号）—— 那是读残的尾节
/// 2. 相邻锚点的间距 ≈ 整数倍中位间距时，中间补**幽灵锚点**（漏读的节）
/// 3. 最后按位置重新编号 1..n（拼图永远从第 1 节开始，表头是固定的）
List<PeriodAnchor> _recoverAnchors(
  List<OcrBlock> sorted,
  double firstColumnLeft,
  double dateRowBottom,
) {
  // ⚠️ 节次栏有**两种写法**，都要认（2026-10-07 真机实测）：
  //   - 裸数字：`1` `2` … `13`（第一款 App）
  //   - `第N节`：`第1节` `第12节`（另一款 App）—— 只认裸数字的话这里
  //     一个锚点都收不到（实测 0 个），节次范围全乱、整列课挤成一格
  //
  // ⚠️ 2026-10-09 起统一走 [parsePeriodToken]，顺带支持中文数字（`一` `十二`）。
  // 它同时排除掉时刻（`08:00`）、周次（`第6周`）、日期（`10月9日`）。
  final List<_PeriodAnchor> raw = <_PeriodAnchor>[];
  for (final OcrBlock b in sorted) {
    final int? p = parsePeriodToken(b.text);
    if (p == null) continue;
    if (b.centerX >= firstColumnLeft) continue; // 课程区里的纯数字是噪声
    // ⚠️ 表头 / 日期行区域里的数字**也不是节次**（2026-10-09 真机实测）：
    // 这款 App 把月份单独写一行 `10月`，OCR 把它拆成 `10` + `2月` ——
    // 那个 `10` 正好落在节次栏的 x 范围内，被当成「第 10 节」收了进去。
    // 后果是整条锚点链错位、**真节次被丢弃**，最后按位置重编号时
    // **所有节次号整体 +1**（课表上第 1-2 节的课被识别成 2-3 节）。
    if (b.centerY < dateRowBottom) continue;
    raw.add(_PeriodAnchor(period: p, centerY: b.centerY));
  }
  if (raw.isEmpty) return const <PeriodAnchor>[];

  final List<double> gaps = <double>[
    for (int i = 1; i < raw.length; i++) raw[i].centerY - raw[i - 1].centerY,
  ]..sort();
  final double medianGap =
      gaps.isEmpty ? 100 : gaps[gaps.length ~/ 2].clamp(20, 100000).toDouble();

  // 1) 按 y 排序收编
  raw.sort((_PeriodAnchor a, _PeriodAnchor b) =>
      a.centerY.compareTo(b.centerY));
  final List<_PeriodAnchor> kept = <_PeriodAnchor>[raw.first];
  for (int i = 1; i < raw.length; i++) {
    final _PeriodAnchor cur = raw[i];
    final _PeriodAnchor last = kept.last;
    // ⚠️ 离上一个锚点太近（不足中位间距的一半）→ 是 ML Kit 误认的噪声，
    // 不是真的节次行（2026-10-09 真机实测：节次 1 和 2 之间凭空冒出一个 `7`，
    // 两者只差 69px，而正常间距是 240）。留着它会挤掉后面的真锚点，
    // 连锁反应是整列节次号偏移。
    if (cur.centerY - last.centerY < medianGap * 0.5) continue;
    if (cur.period > last.period) {
      kept.add(cur);
      continue;
    }
    // 不递增：除非它的位置正好是"下一节"的坑位（读残，如 13→1），否则丢弃
    final double expected = last.centerY + medianGap;
    if ((cur.centerY - expected).abs() <= medianGap * 0.5) {
      kept.add(_PeriodAnchor(period: last.period + 1, centerY: cur.centerY));
    }
  }

  // 2) 大间隔里补幽灵锚点
  final List<_PeriodAnchor> filled = <_PeriodAnchor>[];
  for (int i = 0; i < kept.length; i++) {
    filled.add(kept[i]);
    if (i + 1 >= kept.length) break;
    final double span = kept[i + 1].centerY - kept[i].centerY;
    final int missing = (span / medianGap).round() - 1;
    if (missing >= 1 && span > medianGap * 1.7) {
      for (int k = 1; k <= missing; k++) {
        filled.add(_PeriodAnchor(
          period: 0, // 编号最后统一排，这里不关心
          centerY: kept[i].centerY + span * k / (missing + 1),
        ));
      }
    }
  }

  // 3) 按位置重新编号
  return <PeriodAnchor>[
    for (int i = 0; i < filled.length; i++)
      PeriodAnchor(period: i + 1, centerY: filled[i].centerY),
  ];
}

/// 像素量出的节次行和 OCR 锚点是否互相印证（至少六成对得上）
bool _geometryAgreesWithAnchors(TimetableGeometry geometry,
    List<PeriodAnchor> anchors) {
  if (anchors.isEmpty) return true; // 没有锚点可对，只能信像素
  final double pitch = geometry.medianPitch;
  int hit = 0;
  for (final PeriodAnchor a in anchors) {
    for (final double y in geometry.labelCentersY) {
      if ((y - a.centerY).abs() <= pitch * 0.35) {
        hit++;
        break;
      }
    }
  }
  return hit >= anchors.length * 0.6;
}

// ===========================================================================
// 像素路线
// ===========================================================================

ParsedTimetable _parseWithGeometry({
  required List<OcrBlock> sorted,
  required List<WeekdayColumn> columns,
  required List<PeriodAnchor> anchors,
  required TimetableGeometry geometry,
  required double headerTop,
  required double headerBottom,
  required double dateRowBottom,
  required double maxY,
  required double medianHeight,
}) {
  final double pitch = geometry.medianPitch;

  // ---- 1. 像素块 → 格子骨架（列 + 节次跨度） ----
  List<_GeoCell> cells = <_GeoCell>[];
  for (final GeometryBlock gb in geometry.blocks) {
    final WeekdayColumn? col = _columnAt(columns, gb.centerX);
    if (col == null) continue;
    final List<int> periods = geometry.periodsCovering(gb);
    cells.add(_GeoCell(
      weekday: col.weekday,
      top: gb.top,
      bottom: gb.bottom,
      startPeriod: periods.first,
      endPeriod: periods.last,
      colorEdges: gb.colorEdges,
    ));
  }
  cells.sort((_GeoCell a, _GeoCell b) {
    final int byDay = a.weekday.compareTo(b.weekday);
    if (byDay != 0) return byDay;
    return a.top.compareTo(b.top);
  });

  // ---- 2. 第一轮词表：不跨列的行先归格，用强规则粗拆课名/教室 ----
  final Map<_GeoCell, List<String>> assigned =
      <_GeoCell, List<String>>{};
  // 每个格收到的文字行的 y 跨度 + 文本 —— 只给第一轮用，
  // 用来判断"这一块里到底挤了几门课"（见 _splitCellsByTextGaps）
  final Map<_GeoCell, List<(double, double, String)>> lineSpans =
      <_GeoCell, List<(double, double, String)>>{};
  final List<String> dropped = <String>[];
  // 收到过「未拆整条跨列行」的那些**行**：内容是几列粘一起的，粗拆结果
  // 不可信，不进词表（不然 `云506教室` 这种粘出来的假词会污染修正）。
  // ⚠️ 按行记不按格记：一个脏格里的其他行往往还是干净的
  // （2026-10-07 踩过：按格排除把 `洲梧桐楼` 踢出了词表，DP 切点跟着歪）
  final Set<String> dirtyLines = <String>{};
  _assignAtoms(
    sorted: sorted,
    columns: columns,
    cells: cells,
    assigned: assigned,
    dropped: dropped,
    vocab: null,
    dirtyLines: dirtyLines,
    headerTop: headerTop,
    headerBottom: headerBottom,
    dateRowBottom: dateRowBottom,
    maxY: maxY,
    medianHeight: medianHeight,
    pitch: pitch,
  );

  final TimetableVocab rough = _buildVocab(assigned, dirtyLines);

  // ---- 3. 第二轮：带上词表重拆跨列行、重归格 ----
  //
  // ⚠️ 这一轮的 `lineSpans` 才是**可信的**：跨列粘连行拆开之后，
  // 每一列才拿到属于自己的那几行（第一轮没词表、拆不了，整条长行
  // 按中心归给中间那一列，导致周一少了 3 行文字、切点算偏）。
  assigned.clear();
  dropped.clear();
  _assignAtoms(
    sorted: sorted,
    columns: columns,
    cells: cells,
    assigned: assigned,
    dropped: dropped,
    vocab: rough,
    headerTop: headerTop,
    headerBottom: headerBottom,
    dateRowBottom: dateRowBottom,
    maxY: maxY,
    medianHeight: medianHeight,
    pitch: pitch,
    lineSpans: lineSpans,
  );

  // ---- 3b. 块内按文字纵向间隙切分（相邻课程块可以紧挨着没有白缝） ----
  cells = _splitCellsByTextGaps(cells, lineSpans, geometry);

  // ---- 3c. 第三轮：格子变了，重归一次（拆开的跨列行碎片要落到新格子里） ----
  assigned.clear();
  dropped.clear();
  _assignAtoms(
    sorted: sorted,
    columns: columns,
    cells: cells,
    assigned: assigned,
    dropped: dropped,
    vocab: rough,
    headerTop: headerTop,
    headerBottom: headerBottom,
    dateRowBottom: dateRowBottom,
    maxY: maxY,
    medianHeight: medianHeight,
    pitch: pitch,
  );

  // ---- 4. 格内拆课名/教室 + 词表修正 ----
  final List<ParsedCell> out = <ParsedCell>[];
  final Map<String, int> nameVotes = <String, int>{};
  final List<(_GeoCell, List<String>, List<String>)> split =
      <(_GeoCell, List<String>, List<String>)>[];
  for (final _GeoCell cell in cells) {
    // assigned 的行本来就是按 y 序塞进来的（sorted 按 y 走），不用再排
    final List<String> lines = (assigned[cell] ?? const <String>[])
        .map(cleanOcrLine)
        .where((String s) => s.isNotEmpty)
        .toList();
    if (lines.isEmpty) continue;
    final (List<String>, List<String>) parts = _splitCellLines(lines, rough);
    split.add((cell, parts.$1, parts.$2));
    final String key = squeeze(parts.$1.join());
    if (key.length >= 2 && _cjkCount(key) >= 2) {
      nameVotes[key] = (nameVotes[key] ?? 0) + 1;
    }
  }
  // 课名归一在下面逐格做（_canonicalName 直接用 nameVotes）。
  // 教室修正的**票池用第二轮拆完的教室行**：跨列行拆开的碎片才是纠正形态
  // —— `梧桐洲四教` 在粗词表里只有 1 票（和病句打平），拆完后它有 2 票，
  // 就能赢过只出现 1 次的 `梧桐洲四敦`（2026-10-07 实测踩到）
  final Map<String, int> locCounts = <String, int>{};
  for (final (_GeoCell, List<String>, List<String>) item in split) {
    for (final String line in item.$3) {
      final String t = fixRoomTypos(squeeze(line));
      if (t.isEmpty) continue;
      locCounts[t] = (locCounts[t] ?? 0) + 1;
    }
  }
  final TimetableVocab locVocab = TimetableVocab(
    courseNames: rough.courseNames,
    roomLines: locCounts.keys.toList(),
    roomCounts: locCounts,
  );
  for (final (_GeoCell, List<String>, List<String>) item in split) {
    final _GeoCell cell = item.$1;
    String n = squeeze(item.$2.join());
    // 课名归一：和词表里某条只差一个字时，统一成"票数最高、其次最长"的
    // 那个形态 —— `材料力学A()` → `材料力学A(一)`（别处有一份识别全的）。
    // 必须选一个确定性的形态，不然两个格子会各自往对方翻。
    if (n.isNotEmpty) {
      n = _canonicalName(n, nameVotes);
      // 常见课程词表纠错 —— 投票修不了「所有格子都认错」的情况
      // （用户 2026-10-09 实测：`毛泽东思想和中国特色社会主义理论体系概论`
      //  被认成 `毛淨东…`，而整张表里只有一格有这门课，投票无从纠起）。
      // 判据很严：长度相同 + 差异字里必须有"词表不可能出现的字"，
      // 所以不会把 `美国文学史…` 误纠成 `英国文学史…`（见函数注释）。
      n = correctByCourseVocab(n);
    }
    final StringBuffer locBuf = StringBuffer();
    for (final String line in item.$3) {
      final String t = fixRoomTypos(squeeze(line));
      locBuf.write(locVocab.voteFixRoom(t) ?? t);
    }
    final String loc = locBuf.toString();
    out.add(ParsedCell(
      weekday: cell.weekday,
      top: cell.top,
      bottom: cell.bottom,
      lines: (assigned[cell] ?? const <String>[])
          .map(cleanOcrLine)
          .where((String s) => s.isNotEmpty)
          .toList(),
      spanningSuspicion: n.length < 2 ||
          _cjkCount(n) < 1 ||
          // 「读起来通不通顺」的兜底：课名里不该出现数字，更不该出现教室行。
          // 出现就说明教室被当成课名的一部分粘在了后面（2026-10-08 实测
          // `通用学术英语-听说数406`、`材料力学II(第二层次)数301`），
          // 这种格子在逐格核对页会被标出来提醒重点看
          RegExp(r'[0-9０-９]').hasMatch(n) ||
          looksLikeRoomLine(n),
      startPeriod: cell.startPeriod,
      endPeriod: cell.endPeriod,
      name: n.isEmpty ? null : n,
      location: loc.isEmpty ? null : loc,
    ));
  }

  return ParsedTimetable(
    columns: columns,
    cells: out,
    periodAnchors: anchors,
    navDropped: dropped,
  );
}

class _GeoCell {
  _GeoCell({
    required this.weekday,
    required this.top,
    required this.bottom,
    required this.startPeriod,
    required this.endPeriod,
    this.colorEdges = const <ColorEdge>[],
  });

  final int weekday;
  final double top;
  final double bottom;
  final int startPeriod;
  final int endPeriod;

  /// 这一块里底色变化的 y（来自像素扫描，见 GeometryBlock.colorEdges）
  final List<ColorEdge> colorEdges;

  bool containsY(double y, double tol) => y >= top - tol && y <= bottom + tol;
}

// ===========================================================================
// 块内切分：相邻课程块在像素上可以连成一片，靠文字间隙 / 底色变化分开
// ===========================================================================

/// 把「像素上连成一片」的块按**格内文字的纵向间隙**切开。
///
/// ## 为什么必须切（2026-10-08 真图实测）
///
/// 相邻课程块可以紧挨着、中间**没有白缝**：周一列从 `y=498` 到 `y=1506`
/// 是一整条连续色带（逐行彩色占比实测恒为 1.00，一个 0 都没有）
/// —— 像素扫描只能给出一块，一块里挤了 4 门课。
///
/// ## 三个信号，缺一不可
///
///   1. **教室行 → 课名行**（结构信号，**不依赖间隙大小**）：这个 App 的每个
///      课块都是「课名行… + 教室行」，教室行总在最后 —— 所以「教室行后面跟着
///      一个课名行」就是课与课的分界。
///      ⚠️ 这条专治**同名的两节课**：同名 → App 给同一个底色 → 底色变化线
///      信号失效；课名长的话它俩之间的文字间隙还会被挤到 0.3 个节距
///      （实测周四「程序设计基础」节 5-6 和节 7-8），只剩这条能分开。
///   2. **文字行间隙**：同一门课内部的行间隙只有 30~50px，
///      不同课之间至少 110px（≈0.87 个节距）。间隙 ≥ 0.75 个节距 → 直接切
///   3. **底色变化**：光靠间隙会漏 —— 周四节 1-2 和节 3-4 之间的文字间隙
///      只有 73px（0.58 个节距，比"课名在块顶、教室在块底"的单门课还小），
///      但两块的底色不同（黄 `#fcf8df` → 粉 `#fbebde`）。所以间隙 ≥ 0.5 个
///      节距时，只要间隙里有一条底色变化线，就按它切。
///
/// ## 切完的节次范围
///
/// 上界 = 段内**首个文字行**最近的那个节次（文字行比块边沿更贴近课的真实起点）；
/// 下界 = 非末段 → `min(段覆盖到的末节, 下一段首节 - 1)`
///        （`min` 是防止两门课之间本来就空一节时被硬撑过去）
///        末段 → 段底边**完全罩住**的最后一个节次行，不加容差
///        （块底边是 App 画的、带内边距的边：实测周一末块底边 1506，
///          第 9 节行中心 1543.5 必须排除；夹具里周四跨 4 节的块靠这条兜住）
List<_GeoCell> _splitCellsByTextGaps(
  List<_GeoCell> cells,
  Map<_GeoCell, List<(double, double, String)>> lineSpans,
  TimetableGeometry geometry,
) {
  final double pitch = geometry.medianPitch;
  final int anchorCount = geometry.labelCentersY.length;
  final List<_GeoCell> out = <_GeoCell>[];

  for (final _GeoCell cell in cells) {
    final List<(double, double, String)> spans =
        List<(double, double, String)>.of(
            lineSpans[cell] ?? const <(double, double, String)>[])
          ..sort(((double, double, String) a, (double, double, String) b) =>
              a.$1.compareTo(b.$1));
    if (spans.isEmpty) continue;

    final List<double> cuts = <double>[];
    for (int i = 1; i < spans.length; i++) {
      final (double, double, String) prev = spans[i - 1];
      final (double, double, String) next = spans[i];
      final double gap = next.$1 - prev.$2;

      // 信号①：教室行 → 课名行 = 新的一门课。
      // ⚠️ 这条**不看间隙大小**：同名的两节课在真图上可以贴得很近
      // （App 把它们画成一块同色的连续区域），间隙一小就没有别的信号可用了。
      final bool byRoomLine = looksLikeRoomLine(prev.$3) &&
          !looksLikeRoomLine(next.$3) &&
          _cjkCount(next.$3) >= 2;
      // 其余两个信号要求行与行之间**真的分开**（≥ 1/4 个节距），
      // 否则文字行的上下沿噪声会造出假切点
      if (gap < pitch * 0.25 && !byRoomLine) continue;

      // 信号③：间隙里**最强**的那条底色变化线（不是第一条）——
      // 文字抗锯齿也会蹭出强度 8~10 的假线，而真边界实测 10~18
      ColorEdge? best;
      if (gap >= pitch * 0.5) {
        for (final ColorEdge e in cell.colorEdges) {
          if (e.y <= prev.$2 + 2 || e.y >= next.$1 - 2) continue;
          if (best == null || e.strength > best.strength) best = e;
        }
      }

      if (best != null && best.strength >= 10) {
        cuts.add(best.y);
      } else if (byRoomLine || gap >= pitch * 0.75) {
        cuts.add((prev.$2 + next.$1) / 2);
      }
    }

    final List<double> edges = <double>[cell.top, ...cuts, cell.bottom];
    final List<_GeoCell> segs = <_GeoCell>[];
    for (int i = 0; i + 1 < edges.length; i++) {
      final List<(double, double, String)> seg =
          <(double, double, String)>[
        for (final (double, double, String) s in spans)
          if (s.$1 >= edges[i] && s.$1 < edges[i + 1]) s,
      ];
      if (seg.isEmpty) continue;
      segs.add(_GeoCell(
        weekday: cell.weekday,
        top: edges[i],
        bottom: edges[i + 1],
        startPeriod: _periodNear(geometry, seg.first.$1),
        endPeriod: 1,
      ));
    }
    if (segs.isEmpty) {
      out.add(cell);
      continue;
    }

    for (int i = 0; i < segs.length; i++) {
      final _GeoCell s = segs[i];
      int end;
      if (i + 1 < segs.length) {
        final int byNext = segs[i + 1].startPeriod - 1;
        final int byExtent = _lastPeriodCovering(geometry, s.top, s.bottom);
        end = byExtent < byNext ? byExtent : byNext;
      } else {
        end = _lastPeriodInside(geometry, s.bottom);
      }
      if (end < s.startPeriod) end = s.startPeriod;
      if (end > anchorCount) end = anchorCount;
      out.add(_GeoCell(
        weekday: s.weekday,
        top: s.top,
        bottom: s.bottom,
        startPeriod: s.startPeriod,
        endPeriod: end,
      ));
    }
  }
  return out;
}

/// y 最近的那个节次行是第几节（1 起）。
int _periodNear(TimetableGeometry geometry, double y) {
  int best = 1;
  double bestDist = double.infinity;
  for (int i = 0; i < geometry.labelCentersY.length; i++) {
    final double d = (geometry.labelCentersY[i] - y).abs();
    if (d < bestDist) {
      bestDist = d;
      best = i + 1;
    }
  }
  return best;
}

/// `[top, bottom]` 罩到的最后一个节次行（带容差）—— 给"切点"当底边用。
int _lastPeriodCovering(TimetableGeometry geometry, double top, double bottom) {
  final List<int> p = geometry.periodsCovering(
    GeometryBlock(left: 0, top: top, right: 0, bottom: bottom),
  );
  return p.isEmpty ? 1 : p.last;
}

/// 底边**完全罩住**的最后一个节次行（不加容差）—— 给"块的真实底边"用。
///
/// 块的底边是 App 画出来的、比最后一个节次行低一点点的边（实测内边距
/// ≈0.3 个节距）。加容差会把**下一节**的行也算进来：周一末块底边 1506、
/// 第 9 节行中心 1543.5（差 37.5px，容差 37.8px）—— 就差 0.3px 会多算一节。
int _lastPeriodInside(TimetableGeometry geometry, double bottom) {
  int best = 0;
  for (int i = 0; i < geometry.labelCentersY.length; i++) {
    if (geometry.labelCentersY[i] <= bottom) best = i + 1;
  }
  return best == 0 ? 1 : best;
}

/// OCR 文本行 → 归属到格子。跨列粘连行在这里拆（[vocab] 有词表才拆得准）。
void _assignAtoms({
  required List<OcrBlock> sorted,
  required List<WeekdayColumn> columns,
  required List<_GeoCell> cells,
  required Map<_GeoCell, List<String>> assigned,
  required List<String> dropped,
  required TimetableVocab? vocab,
  Set<String>? dirtyLines,
  Map<_GeoCell, List<(double, double, String)>>? lineSpans,
  required double headerTop,
  required double headerBottom,
  required double dateRowBottom,
  required double maxY,
  required double medianHeight,
  required double pitch,
}) {
  const Set<String> kNavWords = <String>{
    '首页', '课表', '课程表', '成绩', '我的', '日程', '发现', '校园',
  };
  // 日期行：`M-D` / `M/D`，也认**光秃秃的日号**（见 parseTimetable 里的说明）
  final RegExp datePattern = RegExp(r'^\d{1,2}[/\-]\d{1,2}$');
  final RegExp dayOnlyPattern = RegExp(r'^\d{1,2}$');
  bool isAllDateTokens(String t) =>
      t.isNotEmpty &&
      t.split(RegExp(r'\s+')).every((String s) =>
          datePattern.hasMatch(s) || dayOnlyPattern.hasMatch(s));

  for (final OcrBlock src in sorted) {
    final String raw = src.text.trim();
    if (src.bottom <= headerTop + 2) continue;
    if (_looksLikeWeekdayHeader(raw) && src.bottom <= headerBottom + 2) continue;
    if (src.bottom <= dateRowBottom + 2 && isAllDateTokens(raw)) continue;

    // 节次栏（第一列左边那一竖条）里的东西**全都不是课程内容**：节次号、时刻。
    //
    // ⚠️ 2026-10-07 真机实测：原来只丢"纯数字"（`1`/`2`），于是 `09:35`
    // 这种带冒号的时刻漏了过去 —— 它又归不进任何列，被下面
    // 「`?? columns.first.weekday`」的兜底塞进了**周一**，课名直接变成
    // `09:3509:5010:35材料力学A()上10:40`。
    //
    // ⚠️ 但**不能整条丢**（2026-10-08 真机实测）：这个 App 会把「时刻」和
    // 课程内容粘成一行（`08:00-08:50 排球场`、`16:10-17:00 与力学`），
    // 整条丢掉会把教室和课名尾巴一起丢 —— 实测周一丢了「排球场」「与力学」
    // 「204」、周三丢了「层次)」，这些格的教室列全是空。
    // 所以：**整条都在左栏才丢**；伸进第一列的，剥掉行首时刻再用。
    OcrBlock b = src;
    if (b.right <= columns.first.left + 2) continue;
    final String stripped = _stripLeadClock(b.text);
    if (stripped.length != b.text.length) {
      final int cut = b.text.length - stripped.length;
      final double total = _wideUnits(b.text);
      final double frac =
          total <= 0 ? 0 : _wideUnits(b.text.substring(0, cut)) / total;
      b = OcrBlock(
        text: stripped,
        left: b.left + b.width * frac,
        top: b.top,
        right: b.right,
        bottom: b.bottom,
      );
    }
    final String body = b.text.trim();
    if (kNavWords.contains(body) || b.centerY > maxY - medianHeight * 1.2) {
      dropped.add(body);
      continue;
    }

    // 跨列粘连行：拆成每列一份；拆不了（没词表/太怪）就整条按中心归
    final List<(int, String)> pieces = _isSpanning(b, columns)
        ? (vocab == null
            ? <(int, String)>[
                (_columnAt(columns, b.centerX)?.weekday ??
                    columns.first.weekday,
                body),
              ]
            : _splitSpanningLine(b, columns, vocab))
        : <(int, String)>[
            (_columnAt(columns, b.centerX)?.weekday ?? columns.first.weekday,
                body),
          ];

    for (final (int, String) piece in pieces) {
      final String text = cleanOcrLine(piece.$2);
      if (text.isEmpty) continue;
      final int wd = piece.$1;

      // 没落到任何格子里的都是噪声（导航、悬浮球、游离的半个字）。
      // ⚠️ 单字不能一律丢：格子里的「房」是『机房』被换行拆出来的正文
      final _GeoCell? holder = _cellAt(cells, wd, b.centerY, pitch);
      if (holder == null) {
        dropped.add(text);
        continue;
      }
      if (vocab == null && _isSpanning(b, columns) && pieces.length == 1) {
        dirtyLines?.add(text);
      }
      assigned.putIfAbsent(holder, () => <String>[]).add(text);
      lineSpans
          ?.putIfAbsent(holder, () => <(double, double, String)>[])
          .add((b.top, b.bottom, text));
    }
  }
}

/// 这一行是不是横跨了多列（跨列行才需要拆）。
///
/// 两端各内缩 8px 再判：OCR 的行框常比文字宽出一两个像素，
/// `流体力学|`（框 545-715，列边界 550.75）不内缩会被误判成跨列。
bool _isSpanning(OcrBlock b, List<WeekdayColumn> columns) {
  final WeekdayColumn? a = _columnAt(columns, b.left + 8);
  final WeekdayColumn? c = _columnAt(columns, b.right - 8);
  if (a == null || c == null) return false;
  return a.weekday != c.weekday;
}

/// [x] 落在哪一列（按归列边界；出界时取最近的列）
WeekdayColumn? _columnAt(List<WeekdayColumn> columns, double x) {
  for (final WeekdayColumn c in columns) {
    if (x >= c.left && x < c.right) return c;
  }
  WeekdayColumn? best;
  double bestDist = double.infinity;
  for (final WeekdayColumn c in columns) {
    final double d = (x - c.centerX).abs();
    if (d < bestDist) {
      bestDist = d;
      best = c;
    }
  }
  return best;
}

/// y 属于哪一格。
///
/// **严格包含优先于容差包含**：相邻两块可以贴死（缝隙 2px），文字行的
/// 中心带着 ±0.35 行距的容差时会同时落进两块的容差圈里 ——
/// 「工程制图」这个名字行离上块的底只差 42px、离下块的顶 40px，
/// 按列表顺序取第一个就分错了格。严格包含（y 在 [top,bottom] 里）的块
/// 永远赢过只靠容差够到的块；同类里再取最近的。
_GeoCell? _cellAt(List<_GeoCell> cells, int weekday, double y, double pitch) {
  _GeoCell? strictBest;
  double strictDist = double.infinity;
  _GeoCell? looseBest;
  double looseDist = double.infinity;
  for (final _GeoCell c in cells) {
    if (c.weekday != weekday) continue;
    final double d = y < c.top
        ? c.top - y
        : y > c.bottom
            ? y - c.bottom
            : 0;
    if (y >= c.top && y <= c.bottom) {
      if (d < strictDist) {
        strictDist = d;
        strictBest = c;
      }
    } else if (c.containsY(y, pitch * 0.35)) {
      if (d < looseDist) {
        looseDist = d;
        looseBest = c;
      }
    }
  }
  if (strictBest != null) return strictBest;
  if (looseDist <= pitch * 0.6) return looseBest;
  return null;
}

// ===========================================================================
// 跨列粘连行拆分：按字符 x 比例 + 空格痕迹 + 词表，动态规划找最优切法
// ===========================================================================

/// 一条跨列行拆出来的碎片：属于哪个星期、是什么字
class SpanPiece {
  const SpanPiece({required this.weekday, required this.text});
  final int weekday;
  final String text;

  @override
  String toString() => 'SpanPiece(wd$weekday, "$text")';
}

/// 把跨列行 [b] 按列拆开。
///
/// ## 三种线索，动态规划取总分最高的切法
///
///   1. **列边界**：切出来的每段应该完整落在某一列的 x 范围里
///   2. **空格痕迹**：OCR 在列与列的接缝处常留一个空格（`307敦室 A (一)`）
///   3. **词表**：切出来的段是已知的课名 / 楼名 / 教室行才可信；
///      `洲梧桐後|梧桐楼梧桐` 比按列边界硬切的 `洲梧桐後云|杉楼梧桐…` 对
///
/// 字符的 x 按**显示宽度**均分（汉字 1、数字/冒号/连字符半宽；空格不占字宽，
/// 和表头折算同一套约定）。
///
/// ⚠️ 不能按**字符数**均分（2026-10-08 真图实测）：数字只有汉字一半宽，
/// 按字符数算会把窄字符的中心往右推 —— `教301 写`（框 169..292）里第 3 个
/// `1` 的中心被算成 255.1，只比列边界 254.5 靠右 0.6px，于是 DP 认为
/// 「教30」全在第一列、「1写」全在第二列，切点提前一个字，
/// **教室变成 `教30`**（周一的 `教301` 就这么丢了一个字）。
List<(int, String)> _splitSpanningLine(
  OcrBlock b,
  List<WeekdayColumn> columns,
  TimetableVocab vocab,
) {
  final String cleaned = _stripLeadNoise(b.text).replaceAll('|', '');
  // 空格也是信息：记录每个非空白字符后面是不是紧跟空格
  final String raw = cleaned;
  final List<String> chars = <String>[];
  final List<bool> spaceAfter = <bool>[];
  for (int i = 0; i < raw.length; i++) {
    final String ch = raw[i];
    if (_spacePattern.hasMatch(ch)) {
      if (chars.isNotEmpty) spaceAfter[chars.length - 1] = true;
      continue;
    }
    chars.add(ch);
    spaceAfter.add(false);
  }
  final int n = chars.length;
  if (n == 0) return const <(int, String)>[];

  // 每个字符的"显示宽度"以及它左沿之前累积的宽度
  final List<double> unitBefore = <double>[0];
  final List<double> unitW = <double>[];
  for (int i = 0; i < n; i++) {
    final double u = _wideUnits(chars[i]);
    unitW.add(u);
    unitBefore.add(unitBefore[i] + u);
  }
  final double totalUnits = unitBefore[n];
  final double perUnit = totalUnits <= 0 ? b.width / n : b.width / totalUnits;
  double xOf(int i) => b.left + unitBefore[i] * perUnit; // 字符 i 的左沿
  double cxOf(int i) => b.left + (unitBefore[i] + unitW[i] / 2) * perUnit;

  // 每个字符属于哪列（按字符中心）
  final List<int> charCol = <int>[
    for (int i = 0; i < n; i++)
      _columnAt(columns, cxOf(i))?.weekday ?? -1,
  ];

  double segScore(int i, int j) {
    // 段 = chars[i..j)
    final String text = chars.sublist(i, j).join();
    double score = -0.01; // 每段一点成本：同分时偏好切得少
    // 跨列惩罚：段内字符落在了 ≥2 个列里 → 这段横跨了列边界，基本不可信。
    // ⚠️ 两个反例都踩过（2026-10-07）：
    //   - 给"贴合单列"加分 → 每个字切一段反而分最高，词表拼不过
    //   - 空格痕迹加分 → 会诱导把贴边的单字（『云』）从它所属的词里切走。
    // 空格位置交给列边界和词表去判断就够了，不单独加分。
    // 惩罚按"多出的列数"算；压线的字（中心恰好在边界上）靠词表加分拉回来。
    final Set<int> colsInSeg = <int>{
      for (int k = i; k < j; k++) charCol[k],
    }..remove(-1);
    // -2 是试出来的平衡点：-1 时 `室A(一)` 这种跨列段靠"含室字"的
    // 词表加分就能赢（2026-10-07 第四轮迭代踩到）；-2 时它输给正确的
    // 切法，而 D 行压线字造成的轻微跨列靠词表加分仍能拉回来。
    if (colsInSeg.length > 1) score -= 2.0 * (colsInSeg.length - 1);
    // 词表加分只给两字以上的段 —— 单字永远凑不出课名/楼名，
    // 给它加分又会鼓励切碎
    if (j - i >= 2) {
      if (vocab.hasCourse(squeeze(text))) {
        score += 1.5;
      } else if (vocab.hasRoom(squeeze(text)) ||
          kRoomLinePattern.hasMatch(text)) {
        score += 1.5;
      }
    }
    return score;
  }

  // DP：best[j] = 前 j 个字符的最优总分
  const int maxSeg = 14; // 一列一行撑死十几个字
  final List<double> best = List<double>.filled(n + 1, double.negativeInfinity);
  final List<int> from = List<int>.filled(n + 1, -1);
  best[0] = 0;
  for (int j = 1; j <= n; j++) {
    for (int i = (j - maxSeg).clamp(0, n); i < j; i++) {
      if (best[i] == double.negativeInfinity) continue;
      final double s = best[i] + segScore(i, j);
      if (s > best[j]) {
        best[j] = s;
        from[j] = i;
      }
    }
  }

  // 回溯出碎片，按列合并（同列的相邻段是同一条被空格切开的行）
  final List<(int, String)> out = <(int, String)>[];
  int j = n;
  final List<SpanPiece> rev = <SpanPiece>[];
  while (j > 0) {
    final int i = from[j];
    final WeekdayColumn? col = _columnAt(columns, (xOf(i) + xOf(j)) / 2);
    rev.add(SpanPiece(
      weekday: col?.weekday ?? charCol[i],
      text: chars.sublist(i, j).join(),
    ));
    j = i;
  }
  // 先做孤字收编，**再**按列合并 —— 顺序反了的话，孤字会先被粘进
  // 它压线中心所在的列（往往是隔壁列），词表想救都救不回来
  // （2026-10-07 第六轮迭代踩到）。
  final List<SpanPiece> flat = rev.reversed.toList();

  // ---- 孤字收编 ----
  // DP 会把压在列界线上的字切成**孤段**：自己一段就既没有跨列惩罚、
  // 又不用凑词表（单字不给词表加分），成本近乎零 —— 于是『云』被单独
  // 切出来。孤字到底归左边的词还是右边的词，拿词表裁决：
  // 跟哪边拼得上就跟哪边（『云』+『杉楼梧桐』= 词表里的整词 → 归右）。
  for (int k = 0; k < flat.length; k++) {
    if (flat[k].text.length != 1) continue;
    if (!_cjkPattern.hasMatch(flat[k].text)) continue;
    final bool hasLeft = k > 0;
    final bool hasRight = k + 1 < flat.length;
    if (!hasLeft && !hasRight) continue;
    final String withLeft = hasLeft ? flat[k - 1].text + flat[k].text : '';
    final String withRight = hasRight ? flat[k].text + flat[k + 1].text : '';
    // 精确命中 > 模糊命中：『云』往左拼是词表里的 `(实训楼)云`（精确），
    // 往右拼成 `云506教室` 也能模糊蹭上 `506教室` —— 按模糊处理会把
    // 云判给右边（2026-10-07 第八轮踩到）。精确 2 分、模糊 1 分。
    final int leftScore = hasLeft ? _vocabHitScore(vocab, withLeft) : 0;
    final int rightScore = hasRight ? _vocabHitScore(vocab, withRight) : 0;
    // ⚠️ 只有**精确命中**才允许把孤字拽到隔壁列（2026-10-08 真图实测）：
    // 模糊命中（差一个字）什么都可能是 —— 周一的 `写`（周二的课名尾巴）
    // 往左拼成 `教301写`，和词表里的 `教301` 只差一个字，就被拽进了周一，
    // 教室变成 `教301写`。孤字本来就该留在**自己那一列**，除非另一边
    // 有现成的词能对上。
    if (leftScore >= 2 && leftScore > rightScore) {
      flat[k - 1] = SpanPiece(weekday: flat[k - 1].weekday, text: withLeft);
      flat.removeAt(k);
      k--;
    } else if (rightScore >= 2 && rightScore >= leftScore) {
      flat[k + 1] =
          SpanPiece(weekday: flat[k + 1].weekday, text: withRight);
      flat.removeAt(k);
      k--;
    }
  }

  for (final SpanPiece p in flat) {
    if (out.isNotEmpty && out.last.$1 == p.weekday) {
      out[out.length - 1] = (out.last.$1, out.last.$2 + p.text);
    } else {
      out.add((p.weekday, p.text));
    }
  }
  return out;
}

/// 一个 CJK 字（孤字收编用）
final RegExp _cjkPattern = RegExp(r'[一-龥]');

/// 孤字拼进某一边后"像不像个词"：精确命中词表 2 分，模糊（差一字）1 分
int _vocabHitScore(TimetableVocab vocab, String text) {
  if (vocab.courseNames.contains(text) || vocab.roomLines.contains(text)) {
    return 2;
  }
  if (vocab.hasRoom(text) || vocab.hasCourse(text)) return 1;
  return 0;
}

// ===========================================================================
// 格内拆「课名 / 教室」
// ===========================================================================

/// 格内的行分成课名（前段）和教室（后段），返回各自的**行列表**。
///
/// 两条路，词表优先：
///   1. **词表前缀**：把所有行拼起来，看词表里哪条课名是它的前缀
///      （`流体力学` + `梧桐洲三教敦…` → 课名 `流体力学`）。换行边界按
///      逐行累计长度对齐，对不齐（差 1 字以内）才接受
///   2. **强规则**：第一个"像教室行"的行就是教室行起点
///      （课程名几乎不含 楼/室/场/馆/房/敦/教；教室行几乎总含 —— 连被截断的
///      `梧桐楼梧桐` 和被认错字的 `梧桐洲四敦` 都能兜住）。
///      ⚠️ 判据用 [looksLikeRoomLine] 而不是裸的 [kRoomLinePattern]：
///      真图里教室行还有两种"一个教室字都没有"的形态（认错字的 `数301`、
///      被换行拆出来的 `02`），2026-10-08 实测漏了这两类，教室整行被当成
///      课名的一部分（课名变成 `通用学术英语-听说数406`）
(List<String>, List<String>) _splitCellLines(
    List<String> lines, TimetableVocab vocab) {
  if (lines.isEmpty) return (<String>[], <String>[]);
  final String joined = squeeze(lines.join());

  // 0) `@` 分界 —— **最硬的信号，必须排在词表前面**（2026-10-09 真机实测）
  //
  // 这款 App 用 `@` 分隔课名和教室，而且位置**不固定**：
  //   - 行首：`@腾龙楼408教室`（教室行自己以 @ 开头）
  //   - 行尾：`权法@`（课名最后一行以 @ 结尾，教室从下一行开始）
  //
  // ⚠️ 为什么不能只靠下面的词表前缀：词表是**从粗拆结果投票来的**，
  // 而粗拆遇到"课名跨两行"会切错（`英汉/汉` + `英笔译` 被切成课名只有
  // 第一行）—— 错误进了词表，精拆再按错的词表切一遍，**错就固化了**。
  // 真机实测：课名成了 `英汉/汉`、教室成了 `英笔译@腾龙楼408教室`。
  // `@` 是 App 自己画的字符，课程名不可能含它，比任何词表都可靠。
  for (int k = 0; k < lines.length; k++) {
    final String s = squeeze(lines[k]);
    final int at = s.indexOf('@');
    if (at < 0) continue;
    if (at == 0) {
      // @ 在行首 → 这一行及之后全是教室。第一行就是教室的话课名会空掉，
      // 宁可整格都算课名（交给用户改），所以跳出交给下面的强规则
      if (k == 0) break;
      return (lines.sublist(0, k), lines.sublist(k));
    }
    // @ 在行内（含行尾）→ 这一行前半是课名、后半是教室
    final String head = s.substring(0, at);
    final String tail = s.substring(at);
    return (
      <String>[
        ...lines.sublist(0, k),
        if (head.isNotEmpty) head,
      ],
      <String>[tail, ...lines.sublist(k + 1)],
    );
  }

  // 1) 词表前缀
  String? bestVocab;
  for (final String v in vocab.courseNames) {
    if (v.length < 2) continue;
    if (joined.startsWith(v) &&
        (bestVocab == null || v.length > bestVocab.length)) {
      bestVocab = v;
    }
  }
  if (bestVocab != null) {
    int cum = 0;
    for (int k = 0; k < lines.length; k++) {
      cum += squeeze(lines[k]).length;
      if (cum >= bestVocab.length) {
        // 边界要对得上行尾（差 1 字以内），否则词表这条可能不属于这个格
        if (cum - bestVocab.length <= 1) {
          int cut = k + 1;
          // ⚠️ 词表里的课名可能**比真名短**：真图上的课名是 `材料力学A()上`
          // （`(I)上` 被 OCR 认成 `()上`），而词表投票出来的是 `材料力学A` ——
          // 于是 `()上` 被错切给了教室（教室成了 `()上@教2-213`）。
          //
          // 判据：切点后第一行**含括号/数字/字母**（= 明显不是纯汉字的教室碎片）
          // 才往后延到第一个像教室的行为止。
          //
          // ⚠️ **纯汉字碎片一律不动**：那可能是教室名换行后的第一段
          // （`东苑综`+`台楼…`、`紫荆综`+`合楼202`），归教室的事交给强规则那边的
          // 「教室跨行」处理 —— 这里再延一次会把教室碎片推回课名
          // （2026-10-08 真机 + 合成夹具双向实测踩到）。
          final String head = cut < lines.length ? squeeze(lines[cut]) : '';
          if (head.isNotEmpty && RegExp(r'[^\u4e00-\u9fa5]').hasMatch(head)) {
            int rs = cut;
            while (rs < lines.length && !looksLikeRoomLine(lines[rs])) {
              rs++;
            }
            if (rs < lines.length) cut = rs;
          }
          return (
            lines.sublist(0, cut),
            lines.sublist(cut),
          );
        }
        break;
      }
    }
  }

  // 2) 强规则。⚠️ 跳过第 0 行：第一行就当教室行的话课名会空掉，
  //    宁可整格都算课名（交给用户改）
  for (int k = 1; k < lines.length; k++) {
    if (looksLikeRoomLine(lines[k])) {
      int start = k;
      // 教室名**跨行**：真图上 `东苑综合楼…` 会被 OCR 拆成 `东苑综` + `台楼…`，
      // 而 `东苑综` 单独不含 楼/室/场/馆/房/敦/教、也不含数字 —— 看不出是教室，
      // 于是被算进课名（真图周4 7-8 实测：课名成了 `…(Python...东苑综`）。
      // 往上看一行：纯汉字、3~4 字、且课名还剩 ≥ 4 字，就也算教室。
      //
      // ⚠️「课名还剩 ≥ 4 字」这条不能省：真图周3 3-4 的课名
      //   `智能建造技术` 尾行是 `技术境`（3 字纯汉字），去掉它课名只剩
      //   `智慧人`（3 字）—— 那就是把课名切碎。同理周1 7-8 的 `参与`（2 字）
      //   靠长度下限挡住、`层次)`/`据的...`/`2写` 靠「纯汉字」挡住。
      if (start >= 2) {
        final String prev = squeeze(lines[start - 1]);
        final String head = squeeze(lines.sublist(0, start - 1).join());
        final OcrRules rr = ocrRules;
        if (prev.length >= rr.roomSpanMinLen &&
            prev.length <= rr.roomSpanMaxLen &&
            _cjkCount(prev) == prev.length &&
            head.length >= rr.roomSpanMinHead) {
          start -= 1;
        }
      }
      return (lines.sublist(0, start), lines.sublist(start));
    }
  }
  return (lines, <String>[]);
}

/// 从"已经粗拆过"的格子里攒词表。
///
/// 词表要存**行粒度**的教室词（`梧桐楼梧桐` 这种被换行截断的楼名整行存），
/// 拆粘连行时碎片才对得上；课名存去空格的整名。
/// [dirtyCells] 是收到过「未拆整条跨列行」的格子 —— 它们的内容是几列
/// 粘一起的，进词表会产出 `云506教室` 这种假词（2026-10-07 实测踩到）。
TimetableVocab _buildVocab(
  Map<_GeoCell, List<String>> assigned,
  Set<String> dirtyLines,
) {
  final List<String> courses = <String>[];
  final List<String> rooms = <String>[];
  final Map<String, int> roomCounts = <String, int>{};
  void addRoom(String t) {
    if (t.length < 2) return;
    if (!rooms.contains(t)) rooms.add(t);
    roomCounts[t] = (roomCounts[t] ?? 0) + 1;
  }

  for (final List<String> rawLines in assigned.values) {
    final List<String> lines = rawLines
        .map(cleanOcrLine)
        .where((String s) => s.isNotEmpty)
        .where((String s) => !dirtyLines.contains(s))
        .toList();
    if (lines.isEmpty) continue;
    final (List<String>, List<String>) parts =
        _splitCellLines(lines, const TimetableVocab());
    final String name = squeeze(parts.$1.join());
    // ⚠️ 课名候选限长：粗拆时整条跨列行还没拆开，会产出
    // 「四门课名连一起」的假课名（十几个字），进词表会污染拆分。
    // 真课名再长也就十来个字（十几字的选修课名靠强规则拆，不靠词表）。
    if (name.length >= 2 && name.length <= 12 && _cjkCount(name) >= 2) {
      if (!courses.contains(name)) courses.add(name);
    }
    for (final String line in parts.$2) {
      // 教室行整行进词表；带括号的再按括号拆一份（(实训楼) 独立成词）
      addRoom(fixRoomTypos(squeeze(line)));
      final List<String> byParen = line.split(RegExp(r'[()]'));
      if (byParen.length > 1) {
        for (final String t in byParen) {
          addRoom(fixRoomTypos(squeeze(t)));
        }
      }
    }
  }
  return TimetableVocab(
    courseNames: courses,
    roomLines: rooms,
    roomCounts: roomCounts,
  );
}

int _cjkCount(String s) {
  int n = 0;
  for (int i = 0; i < s.length; i++) {
    final int c = s.codeUnitAt(i);
    if (c >= 0x4E00 && c <= 0x9FFF) n++;
  }
  return n;
}

/// 在词表里给 [name] 找一个确定性的"标准形态"：
/// 和它完全相等或只差一个字（编辑距离 ≤1）的候选里，
/// 票数最高的优先，同票取更长的（`材料力学A(一)` 胜过 `材料力学A()`），
/// 再同取字典序小的。没有候选就原样返回。
String _canonicalName(String name, Map<String, int> votes) {
  String? best;
  int bestVotes = -1;
  for (final String v in votes.keys) {
    final bool exact = v == name;
    final bool near = v.length >= 4 &&
        (v.length - name.length).abs() <= 1 &&
        _editDistanceAtMost1(v, name);
    if (!exact && !near) continue;
    final int votesOf = votes[v] ?? 0;
    if (votesOf > bestVotes ||
        (votesOf == bestVotes &&
            best != null &&
            (v.length > best.length ||
                (v.length == best.length && v.compareTo(best) < 0)))) {
      best = v;
      bestVotes = votesOf;
    }
  }
  return best ?? name;
}

/// 编辑距离是否 ≤1（课名都是短串，O(n²) 的完整 DP 也够快）
bool _editDistanceAtMost1(String a, String b) {
  if (a == b) return true;
  if ((a.length - b.length).abs() > 1) return false;
  // 逐字符找第一处不同，分「替换 / 插入 / 删除」三种情况核对余下部分
  int i = 0;
  while (i < a.length && i < b.length && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  if (i == a.length) return b.length - a.length <= 1;
  if (i == b.length) return a.length - b.length <= 1;
  // 替换：跳过两边的这一位
  if (a.length == b.length) {
    return a.substring(i + 1) == b.substring(i + 1);
  }
  // 插入/删除：长串跳过这一位再比
  final String longer = a.length > b.length ? a : b;
  final String shorter = a.length > b.length ? b : a;
  return longer.substring(i + 1) == shorter.substring(i);
}

// ===========================================================================
// 纯文字路线（兜底）：旧的间距聚格 + 最近节次
// ===========================================================================

ParsedTimetable _parseTextOnly({
  required List<OcrBlock> sorted,
  required List<WeekdayColumn> columns,
  required List<PeriodAnchor> anchors,
  required double headerTop,
  required double headerBottom,
  required double dateRowBottom,
  required double maxY,
  required double medianHeight,
  required double firstColumnLeft,
}) {
  final RegExp numberPattern = RegExp(r'^\d{1,2}$');
  const Set<String> kNavWords = <String>{
    '首页', '课表', '课程表', '成绩', '我的', '日程', '发现', '校园',
  };
  final RegExp datePattern = RegExp(r'^\d{1,2}-\d{1,2}$');
  final double cellGapThreshold = medianHeight * 1.8;

  final List<String> navDropped = <String>[];
  final Map<int, List<OcrBlock>> buckets = <int, List<OcrBlock>>{};
  bool isAllDateTokens(String t) =>
      t.isNotEmpty && t.split(RegExp(r'\s+')).every(datePattern.hasMatch);
  for (final OcrBlock b in sorted) {
    final String t = b.text.trim();
    if (b.bottom <= headerTop + 2) continue;
    if (_looksLikeWeekdayHeader(t) && b.bottom <= headerBottom + 2) continue;
    if (b.bottom <= dateRowBottom + 2 && isAllDateTokens(t)) continue;
    // 节次栏里的一切都不是课程内容（见 `_assignAtoms` 里的同款说明）
    if (b.centerX < firstColumnLeft) continue;
    if (kNavWords.contains(t) || b.centerY > maxY - medianHeight * 1.2) {
      navDropped.add(t);
      continue;
    }
    if (t.length == 1 && !numberPattern.hasMatch(t)) {
      navDropped.add(t);
      continue;
    }
    if (RegExp(r'^\d+$').hasMatch(t)) {
      navDropped.add(t);
      continue;
    }
    int? column;
    for (final WeekdayColumn c in columns) {
      if (b.centerX >= c.left && b.centerX < c.right) {
        column = c.weekday;
        break;
      }
    }
    column ??= (b.centerX < columns.first.left)
        ? columns.first.weekday
        : columns.last.weekday;
    buckets.putIfAbsent(column, () => <OcrBlock>[]).add(b);
  }

  final List<ParsedCell> cells = <ParsedCell>[];
  for (final WeekdayColumn column in columns) {
    final List<OcrBlock> bucket = buckets[column.weekday] ?? const <OcrBlock>[];
    if (bucket.isEmpty) continue;
    bucket.sort((OcrBlock a, OcrBlock b) => a.top.compareTo(b.top));

    final double colWidth = column.right - column.left;
    List<OcrBlock> current = <OcrBlock>[bucket.first];
    void flush() {
      final double top = current
          .map((OcrBlock b) => b.top)
          .reduce((double a, double b) => a < b ? a : b);
      final double bottom = current
          .map((OcrBlock b) => b.bottom)
          .reduce((double a, double b) => a > b ? a : b);
      final bool spanning = current.any((OcrBlock b) => b.width > colWidth * 1.5);
      final List<OcrBlock> ordered = List<OcrBlock>.of(current)
        ..sort((OcrBlock a, OcrBlock b) => a.top.compareTo(b.top));
      cells.add(ParsedCell(
        weekday: column.weekday,
        top: top,
        bottom: bottom,
        lines: ordered.map((OcrBlock b) => b.text.trim()).toList(),
        spanningSuspicion: spanning,
        startPeriod: _periodAt(anchors, top),
        endPeriod: _periodAt(anchors, bottom),
      ));
    }

    for (int i = 1; i < bucket.length; i++) {
      final double prevBottom = current
          .map((OcrBlock b) => b.bottom)
          .reduce((double a, double b) => a > b ? a : b);
      if (bucket[i].top - prevBottom > cellGapThreshold) {
        flush();
        current = <OcrBlock>[bucket[i]];
      } else {
        current.add(bucket[i]);
      }
    }
    flush();
  }

  return ParsedTimetable(
    columns: columns,
    cells: cells,
    periodAnchors: anchors,
    navDropped: navDropped,
  );
}

int _weekdayNumber(String hanzi) {
  const List<String> names = <String>['一', '二', '三', '四', '五', '六', '日'];
  final int i = names.indexOf(hanzi);
  return i >= 0 ? i + 1 : 7; // 「天」兜底为周日
}

/// y 离哪个节的锚点最近就算哪一节。格是竖着跨行的，取上沿/下沿各判一次。
int? _periodAt(List<PeriodAnchor> anchors, double y) {
  if (anchors.isEmpty) return null;
  PeriodAnchor best = anchors.first;
  double bestDist = (y - best.centerY).abs();
  for (final PeriodAnchor a in anchors.skip(1)) {
    final double d = (y - a.centerY).abs();
    if (d < bestDist) {
      best = a;
      bestDist = d;
    }
  }
  return best.period;
}

class _HeaderPart {
  const _HeaderPart({
    required this.weekday,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });
  final int weekday;
  final double left;
  final double right;
  final double top;
  final double bottom;
}

/// 裸表头扫描结果
class _BareHeaderScan {
  const _BareHeaderScan({required this.columns, required this.labelParts});

  /// 用于建列的星期位置（可能含从日期行推导出来的）
  final List<_HeaderPart> columns;

  /// **只含真正的表头标签** —— 调用方用它定表头行的上下沿
  final List<_HeaderPart> labelParts;
}

/// 裸表头（`一 二 三 四 五 六 日`，没有「周」字）+ 日期行 → 补齐 7 列星期。
///
/// 触发条件与理由见 `parseTimetable` 里调用点的注释。核心是两条腿走路：
///   - **位置**来自日期行（`11/2 11/3 …`）：7 个都在、间距天然就是列距
///   - **身份**来自标签：认得出的那三四个（`三四`/`五`/`六`/`日m`）当锚点，
///     按列距把位置翻译成星期号
///
/// 两边一配，ML Kit 漏读的「一」「二」也就补回来了。
_BareHeaderScan? _bareHeaderScan(
  List<OcrBlock> sorted,
  double maxY,
  double medianHeight,
) {
  // ---- ① 表头标签：连续的周几字（允许 `日m` 这种带非汉字尾巴的） ----
  //
  // ⚠️ 为什么卡 y < 45%：底部导航栏的「三」（三条杠那个图标）也是一个
  // 孤立的「三」字块，不卡 y 会被当成周三的表头。
  final double yLimit = maxY * 0.45;
  final RegExp lead = RegExp(r'^[一二三四五六日天]+');
  final List<_HeaderPart> labels = <_HeaderPart>[];
  for (final OcrBlock b in sorted) {
    if (b.top > yLimit) continue;
    final String dense =
        _stripLeadNoise(b.text).replaceAll(_spacePattern, '');
    // ⚠️ 长度上限是 **7**（一周最多 7 天），不是 3。
    //
    // 2026-10-08 真机实测：ML Kit 会把「一」「二」整块漏读（细横线字形），
    // 剩下的 `三 四 五 六` **粘成一个块**（dense = `三四五六`，长度 4）——
    // 卡在 3 就把整行表头跳过了，只剩孤零零一个 `日`，兜底直接放弃
    // （用户看到的就是"表头没有『周』字就识别不出来"）。
    // 反正下面「尾巴还有汉字就跳过」那条已经能挡住 `三教` 这类正文，
    // 长度本身不必卡死。
    if (dense.isEmpty || dense.length > 7) continue;
    final RegExpMatch? m = lead.firstMatch(dense);
    if (m == null) continue;
    final String run = m.group(0)!;
    // 尾巴还有汉字 → 是正文（`三教` 之类），不是表头
    if (_cjkCount(dense.substring(run.length)) > 0) continue;
    // 一个块里可能有多个周几（`三四`、`五 六`）—— 按字符均分给 x 区间。
    // ⚠️ 这里的 x 只是近似（块里夹的空格不占字宽），下面会拿日期行校正。
    for (int i = 0; i < run.length; i++) {
      final double half = b.width / dense.length / 2;
      final double cx = b.left + b.width * ((i + 0.5) / dense.length);
      labels.add(_HeaderPart(
        weekday: _weekdayNumber(run[i]),
        left: cx - half,
        right: cx + half,
        top: b.top,
        bottom: b.bottom,
      ));
    }
  }
  if (labels.isEmpty) return null;

  // 表头一定在同一横排：按中心线聚类，取最大的那一簇
  final List<_HeaderPart> labelRow = _largestRow(labels, medianHeight);
  if (labelRow.length < 2) return null;

  final double rowTop = labelRow
      .map((_HeaderPart h) => h.top)
      .reduce((double a, double b) => a < b ? a : b);
  final double rowBottom = labelRow
      .map((_HeaderPart h) => h.bottom)
      .reduce((double a, double b) => a > b ? a : b);

  // ---- ② 日期行：表头正下方那一排日期（判据见 [looksLikeDateToken]）----
  //
  // ⚠️ 这里以前自己写了一份 `^\d{1,2}[/\-]\d{1,2}$`，**只认带分隔符的写法**。
  // 而这款 App 写的是**纯日号 `12 13 14…`**（月份单独一行 `10月`）→
  // 整排日期一个都提不到 → 兜底的"位置来源"失效 → 「一」「二」漏读后
  // 补不齐 7 列（2026-10-09 真机实测：13 门课只剩 7 格）。
  // 现在和主流程共用同一个判据，**别再分家**。
  final List<_HeaderPart> dates = <_HeaderPart>[];
  for (final OcrBlock b in sorted) {
    if (b.top < rowTop - 20 || b.top > rowBottom + 140) continue;
    if (!looksLikeDateToken(b.text)) continue;
    dates.add(_HeaderPart(
      weekday: 0,
      left: b.left,
      right: b.right,
      top: b.top,
      bottom: b.bottom,
    ));
  }
  dates.sort((_HeaderPart a, _HeaderPart b) =>
      ((a.left + a.right) / 2).compareTo((b.left + b.right) / 2));

  // ---- ③ 列距：优先用日期行（间距天然均匀），没有就退回标签 ----
  double pitch = _medianPitch(dates);
  if (pitch <= 0) pitch = _medianPitch(labelRow, byWeekdayOrder: true);
  if (pitch <= 0) return null;

  // ---- ④ 身份锚点：找一对「标签 ↔ 日期」最贴近的，用它把位置翻译成星期 ----
  final Map<int, _HeaderPart> byWeekday = <int, _HeaderPart>{};
  int? anchorWeekday;
  double anchorX = 0;
  double bestDist = double.infinity;
  for (final _HeaderPart l in labelRow) {
    final double lx = (l.left + l.right) / 2;
    for (final _HeaderPart d in dates) {
      final double dx = (d.left + d.right) / 2;
      final double dist = (dx - lx).abs();
      if (dist < bestDist) {
        bestDist = dist;
        anchorWeekday = l.weekday;
        anchorX = dx;
      }
    }
  }

  // 日期在列里居中、7 个都在 —— **位置以日期为准**（标签那个 x 是近似值）
  //
  // ⚠️ 这里必须**重新构造** `_HeaderPart` 并把真正的星期号写进 `weekday` 字段。
  // 直接塞 `dates` 里的原件是不行的：那些件的 `weekday` 是占位值 0，
  // 星期号只在 Map 的 key 上 —— 调用方按 `h.weekday` 合并时 7 列会全塌成
  // 一个 key `0`（2026-10-07 踩到，表现为"7 列变成 1 列"）。
  if (anchorWeekday != null) {
    for (final _HeaderPart d in dates) {
      final double dx = (d.left + d.right) / 2;
      final int w = anchorWeekday + ((dx - anchorX) / pitch).round();
      if (w < 1 || w > 7) continue;
      byWeekday[w] = _HeaderPart(
        weekday: w,
        left: d.left,
        right: d.right,
        top: d.top,
        bottom: d.bottom,
      );
    }
  }
  // 日期行没有的星期，退回标签自己的位置
  for (final _HeaderPart l in labelRow) {
    byWeekday.putIfAbsent(l.weekday, () => l);
  }

  // ---- ⑤ 还缺的星期：按列距往外推 ----
  //
  // ⚠️ 只在**可见范围内**补：截图横向滚过、周一整列在画面外时，
  // 凭空在左边造一列会把节次栏的数字也吃进课程区。
  final List<int> known = byWeekday.keys.toList()..sort();
  final List<double> knownX = byWeekday.values
      .map((_HeaderPart h) => (h.left + h.right) / 2)
      .toList()
    ..sort();
  for (int w = 1; w <= 7; w++) {
    if (byWeekday.containsKey(w)) continue;
    int base = known.first;
    for (final int k in known) {
      if ((k - w).abs() < (base - w).abs()) base = k;
    }
    final double bx = (byWeekday[base]!.left + byWeekday[base]!.right) / 2;
    final double x = bx + (w - base) * pitch;
    if (x < knownX.first - pitch * 0.55) continue;
    if (x > knownX.last + pitch * 0.55) continue;
    byWeekday[w] = _HeaderPart(
      weekday: w,
      left: x - 1,
      right: x + 1,
      top: rowTop,
      bottom: rowBottom,
    );
  }

  if (byWeekday.length < kMinWeekdayColumns) return null;
  final List<_HeaderPart> columns = byWeekday.values.toList()
    ..sort((_HeaderPart a, _HeaderPart b) => a.weekday.compareTo(b.weekday));
  return _BareHeaderScan(columns: columns, labelParts: labelRow);
}

/// 取「中心线接近」的一簇里最大的那一簇 —— 表头永远在同一横排
List<_HeaderPart> _largestRow(List<_HeaderPart> parts, double tolerance) {
  final List<_HeaderPart> sorted = List<_HeaderPart>.of(parts)
    ..sort((_HeaderPart a, _HeaderPart b) =>
        ((a.top + a.bottom) / 2).compareTo((b.top + b.bottom) / 2));
  List<_HeaderPart> best = const <_HeaderPart>[];
  int i = 0;
  while (i < sorted.length) {
    final double y0 = (sorted[i].top + sorted[i].bottom) / 2;
    final List<_HeaderPart> run = <_HeaderPart>[];
    while (i < sorted.length &&
        (((sorted[i].top + sorted[i].bottom) / 2) - y0).abs() <= tolerance) {
      run.add(sorted[i]);
      i++;
    }
    if (run.length > best.length) best = run;
  }
  return best;
}

/// 相邻中心距的中位数。
///
/// [byWeekdayOrder] = true 时按**星期号**排序再量（标签在块里的顺序不可靠，
/// 但星期号可靠）；否则按 x 排序（日期行本来就是从左到右）。
double _medianPitch(List<_HeaderPart> parts, {bool byWeekdayOrder = false}) {
  if (parts.length < 2) return 0;
  final List<_HeaderPart> sorted = List<_HeaderPart>.of(parts);
  if (byWeekdayOrder) {
    sorted.sort(
        (_HeaderPart a, _HeaderPart b) => a.weekday.compareTo(b.weekday));
  } else {
    sorted.sort((_HeaderPart a, _HeaderPart b) =>
        ((a.left + a.right) / 2).compareTo((b.left + b.right) / 2));
  }
  final List<double> gaps = <double>[];
  for (int i = 1; i < sorted.length; i++) {
    // 按星期排序时，两个标签可能隔着几个星期（漏读），要除以跨的格数
    final int step =
        byWeekdayOrder ? (sorted[i].weekday - sorted[i - 1].weekday) : 1;
    if (step <= 0) continue;
    gaps.add((((sorted[i].left + sorted[i].right) / 2) -
            ((sorted[i - 1].left + sorted[i - 1].right) / 2)) /
        step);
  }
  if (gaps.isEmpty) return 0;
  gaps.sort();
  return gaps[gaps.length ~/ 2];
}

class _PeriodAnchor {
  const _PeriodAnchor({required this.period, required this.centerY});
  final int period;
  final double centerY;
}
