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

import 'ocr_result.dart';
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
bool _looksLikeWeekdayHeader(String raw) =>
    _weekdayLeadPattern.hasMatch(_stripLeadNoise(raw));

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

  // ---- 2. 日期行：表头正下方、`M-D` 形态 ----
  final RegExp datePattern = RegExp(r'^\d{1,2}-\d{1,2}$');
  double dateRowBottom = headerBottom;
  for (final OcrBlock b in sorted) {
    if (b.top < headerBottom || b.top > headerBottom + 80) continue;
    final List<String> tokens = b.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((String s) => s.isNotEmpty)
        .toList();
    if (tokens.isEmpty || !tokens.every(datePattern.hasMatch)) continue;
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
      _recoverAnchors(sorted, columns.first.left);

  // ---- 4. 分流：像素路线 / 纯文字路线 ----
  final double maxY = sorted
      .map((OcrBlock b) => b.bottom)
      .reduce((double a, double b) => a > b ? a : b);
  final List<double> heights =
      sorted.map((OcrBlock b) => b.height).toList()..sort();
  final double medianHeight = heights[heights.length ~/ 2];

  if (pixels != null) {
    final TimetableGeometry? geometry = TimetableGeometryScanner.analyze(
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
List<PeriodAnchor> _recoverAnchors(List<OcrBlock> sorted, double firstColumnLeft) {
  final RegExp numberPattern = RegExp(r'^\d{1,2}$');
  final List<_PeriodAnchor> raw = <_PeriodAnchor>[];
  for (final OcrBlock b in sorted) {
    final String t = b.text.trim();
    if (!numberPattern.hasMatch(t)) continue;
    if (b.centerX >= firstColumnLeft) continue; // 课程区里的纯数字是噪声
    raw.add(_PeriodAnchor(period: int.parse(t), centerY: b.centerY));
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
  final List<_GeoCell> cells = <_GeoCell>[];
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
  final List<String> dropped = <String>[];
  // 收到过「未拆整条跨列行」的那些**行**：内容是几列粘一起的，粗拆结果
  // 不可信，不进词表（不然 `云506教室` 这种粘出来的假词会污染修正）。
  // ⚠️ 按行记不按格记：一个脏格里的其他行往往还是干净的
  // （2026-10-07 踩过：按格排除把 `洲云杉楼` 踢出了词表，DP 切点跟着歪）
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
  // —— `云杉洲四教` 在粗词表里只有 1 票（和病句打平），拆完后它有 2 票，
  // 就能赢过只出现 1 次的 `云杉洲四敦`（2026-10-07 实测踩到）
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
      spanningSuspicion: n.length < 2 || _cjkCount(n) < 1,
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
  });

  final int weekday;
  final double top;
  final double bottom;
  final int startPeriod;
  final int endPeriod;

  bool containsY(double y, double tol) => y >= top - tol && y <= bottom + tol;
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
  required double headerTop,
  required double headerBottom,
  required double dateRowBottom,
  required double maxY,
  required double medianHeight,
  required double pitch,
}) {
  final RegExp numberPattern = RegExp(r'^\d{1,2}$');
  const Set<String> kNavWords = <String>{
    '首页', '课表', '课程表', '成绩', '我的', '日程', '发现', '校园',
  };
  final RegExp datePattern = RegExp(r'^\d{1,2}-\d{1,2}$');
  bool isAllDateTokens(String t) =>
      t.isNotEmpty && t.split(RegExp(r'\s+')).every(datePattern.hasMatch);

  for (final OcrBlock b in sorted) {
    final String raw = b.text.trim();
    if (b.bottom <= headerTop + 2) continue;
    if (_looksLikeWeekdayHeader(raw) && b.bottom <= headerBottom + 2) continue;
    if (b.bottom <= dateRowBottom + 2 && isAllDateTokens(raw)) continue;
    if (numberPattern.hasMatch(raw) && b.centerX < columns.first.left) continue;
    if (kNavWords.contains(raw) || b.centerY > maxY - medianHeight * 1.2) {
      dropped.add(raw);
      continue;
    }

      // 跨列粘连行：拆成每列一份；拆不了（没词表/太怪）就整条按中心归
    final List<(int, String)> pieces = _isSpanning(b, columns)
        ? (vocab == null
            ? <(int, String)>[
                (_columnAt(columns, b.centerX)?.weekday ??
                    columns.first.weekday,
                raw),
              ]
            : _splitSpanningLine(b, columns, vocab))
        : <(int, String)>[
            (_columnAt(columns, b.centerX)?.weekday ?? columns.first.weekday,
                raw),
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
///      `洲云杉後|云杉楼云杉` 比按列边界硬切的 `洲云杉後云|杉楼云杉…` 对
///
/// 字符的 x 按非空白字符数均分（和表头折算同一套逻辑，空格不占字宽）。
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

  final double charW = b.width / n;
  double xOf(int i) => b.left + i * charW; // 字符 i 的左沿
  double cxOf(int i) => b.left + (i + 0.5) * charW;

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
  // 跟哪边拼得上就跟哪边（『云』+『杉楼云杉』= 词表里的整词 → 归右）。
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
    if (leftScore > rightScore) {
      flat[k - 1] = SpanPiece(weekday: flat[k - 1].weekday, text: withLeft);
      flat.removeAt(k);
      k--;
    } else if (rightScore > 0 && rightScore >= leftScore) {
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
///      （`流体力学` + `云杉洲三教敦…` → 课名 `流体力学`）。换行边界按
///      逐行累计长度对齐，对不齐（差 1 字以内）才接受
///   2. **强规则**：第一个含 楼/室/场/馆/房/敦 的行就是教室行起点
///      （课程名几乎不含这些字；教室行几乎总含 —— 连被截断的
///      `云杉楼云杉` 和被认错字的 `云杉洲四敦` 都能兜住）
(List<String>, List<String>) _splitCellLines(
    List<String> lines, TimetableVocab vocab) {
  if (lines.isEmpty) return (<String>[], <String>[]);
  final String joined = squeeze(lines.join());

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
          return (
            lines.sublist(0, k + 1),
            lines.sublist(k + 1),
          );
        }
        break;
      }
    }
  }

  // 2) 强规则
  for (int k = 0; k < lines.length; k++) {
    if (kRoomLinePattern.hasMatch(lines[k])) {
      return (lines.sublist(0, k), lines.sublist(k));
    }
  }
  return (lines, <String>[]);
}

/// 从"已经粗拆过"的格子里攒词表。
///
/// 词表要存**行粒度**的教室词（`云杉楼云杉` 这种被换行截断的楼名整行存），
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
    if (numberPattern.hasMatch(t) && b.centerX < firstColumnLeft) continue;
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

class _PeriodAnchor {
  const _PeriodAnchor({required this.period, required this.centerY});
  final int period;
  final double centerY;
}
