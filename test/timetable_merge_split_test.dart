import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/ocr/ocr_result.dart';
import 'package:pomodoro/domain/ocr/timetable_grid.dart';

/// 课表解析「相邻课程块在像素上连成一片」的回归。
///
/// 坐标是**合成**的（不写真名楼名），但结构照 2026-10-08 的真图搭：
/// 这个 App 的相邻课块**紧挨着、中间没有白缝**，一块里可以挤好几门课。
///
/// 钉住的四件事（前三条都是真图上踩出来的）：
///
///   1. **左栏扫描会多认出一堆假节次行**：课程文字的左边缘比列边界还靠左
///      （列边界是按粘成一块的表头按字符均分算的），最左边十几像素落进
///      "左栏"就成了假节次行，还会把真节次行粘连后挤掉。像素 pitch 会从
///      150 掉到 115 → 所有块的节次范围全错。**以 OCR 锚点为准**才修得好。
///   2. **块内切分**：间隙 ≥ 0.75 个节距 → 直接切；间隙在 0.5~0.75 之间时
///      看**间隙里有没有底色变化线**（App 给每门课一个底色，这就是分界）。
///   3. **同色 + 小间隙不能切**：单门课"课名在块顶、教室在块底"的间隙
///      也可能不小，切了就把一门课拆成两格。
///   4. **块底边严格界定末节**：块底边是 App 画的、带内边距的边，
///      下一节的节次行中心就贴在它下面，加容差会多算一节。
OcrBlock b(double l, double t, double r, double bo, String text) =>
    OcrBlock(text: text, left: l, top: t, right: r, bottom: bo);

const int kPeriods = 6;
const List<double> kPeriodY = <double>[300, 450, 600, 750, 900, 1050];
const double kPitch = 150;

/// 合成 OCR：5 列 × 6 节；周一的课名**故意从列边界左边开始**（造假节次行）
final List<OcrBlock> fixture = <OcrBlock>[
  // 星期表头（中心决定列边界：120 / 300 / 480 / 660 / 840 / 1020）
  b(180, 180, 240, 210, '周一'),
  b(360, 180, 420, 210, '周二'),
  b(540, 180, 600, 210, '周三'),
  b(720, 180, 780, 210, '周四'),
  b(900, 180, 960, 210, '周五'),
  // 日期行：**光秃秃的日号**（这个 App 就是这么写的，不认就会混进课名）
  b(200, 240, 220, 260, '1'),
  b(380, 240, 400, 260, '2'),
  b(560, 240, 580, 260, '3'),
  b(740, 240, 760, 260, '4'),
  b(920, 240, 940, 260, '5'),
  // 节次栏
  for (int i = 0; i < kPeriods; i++)
    b(16, kPeriodY[i] - 14, 50, kPeriodY[i] + 14, '${i + 1}'),
  // ---- 周一：两块**贴死**、底色不同；课名左边缘压在列边界左边 ----
  b(112, 290, 250, 320, '枫林课'),
  b(150, 330, 280, 360, '枫林楼101'),
  b(112, 700, 250, 730, '紫荆课'),
  b(150, 740, 280, 770, '紫荆楼202'),
  // ---- 周二：两块贴死、**同一个底色**，靠大间隙切 ----
  b(305, 290, 440, 320, '枫林课'),
  b(340, 330, 470, 360, '枫林楼101'),
  b(305, 700, 440, 730, '紫荆课'),
  b(340, 740, 470, 770, '紫荆楼202'),
  // ---- 周三：间隙只有 0.53 个节距，只能靠底色变化线切 ----
  b(485, 290, 620, 320, '枫林课'),
  b(520, 330, 650, 360, '枫林楼101'),
  b(485, 440, 620, 470, '紫荆课'),
  b(520, 480, 650, 510, '紫荆楼202'),
  // ---- 周四：一门课、块内只有课名和教室两行 ----
  b(665, 290, 800, 320, '枫林课'),
  b(700, 330, 830, 360, '枫林楼101'),
  // ---- 周五：块底边只到第 5 节（第 6 节行在它下面） ----
  b(845, 290, 980, 320, '枫林课'),
  b(880, 330, 1010, 360, '枫林楼101'),
  // 底部导航（抬高 maxY，本身要被丢掉）
  b(400, 1120, 600, 1150, '首页'),
];

/// 合成像素：节次标签 + 课程色块（相邻块**贴死**，没有白缝）+ 文字左边缘
TimetablePixels buildPixels() {
  const int w = 1000, h = 1200;
  final Uint8List px = Uint8List(w * h * 4);
  void fill(int r, int g, int bl) {
    for (int i = 0; i < w * h; i++) {
      px[i * 4] = r;
      px[i * 4 + 1] = g;
      px[i * 4 + 2] = bl;
      px[i * 4 + 3] = 255;
    }
  }

  void rect(double l, double t, double r, double bo, int rr, int gg, int bb) {
    for (int y = t.round(); y <= bo.round() && y < h; y++) {
      for (int x = l.round(); x <= r.round() && x < w; x++) {
        final int p = (y * w + x) * 4;
        px[p] = rr;
        px[p + 1] = gg;
        px[p + 2] = bb;
      }
    }
  }

  fill(255, 255, 255);
  // 节次标签（暗色低饱和）
  for (final double y in kPeriodY) {
    rect(16, y - 14, 50, y + 14, 70, 70, 70);
  }
  // 周一：粉 → 米黄（两块贴死，过渡线落在文字间隙里）
  rect(120, 280, 300, 680, 240, 200, 200);
  rect(120, 680, 300, 1060, 250, 240, 200);
  // 周二：整块同色
  rect(300, 280, 480, 1060, 200, 230, 200);
  // 周三：红 → 蓝（过渡线落在 0.53 个节距的小间隙里）
  rect(480, 280, 660, 400, 230, 180, 180);
  rect(480, 400, 660, 1060, 180, 190, 230);
  // 周四：整块同色
  rect(660, 280, 840, 1060, 235, 195, 130);
  // 周五：整块同色，底边只到第 5 节下面一点
  rect(840, 280, 1020, 1020, 150, 205, 150);
  // 文字：把每个 OCR 文本块的**左边缘**画成暗块（真图里文字就是这样
  // 把最左边十几像素伸进"左栏"的 —— 不画出来就测不到假节次行）
  for (final OcrBlock blk in fixture) {
    if (blk.top < 280 || blk.top > 1000) continue;
    final double wPart = (blk.right - blk.left) * 0.18;
    rect(blk.left, blk.top + 6, blk.left + wPart, blk.bottom - 6, 40, 40, 40);
  }
  return TimetablePixels(width: w, height: h, rgba: px);
}

void main() {
  late ParsedTimetable parsed;

  setUpAll(() {
    parsed = parseTimetable(fixture, pixels: buildPixels());
  });

  ParsedCell cell(int weekday, int startPeriod) => parsed.cells.firstWhere(
        (ParsedCell c) =>
            c.weekday == weekday && c.startPeriod == startPeriod,
        orElse: () => throw StateError('没有 周$weekday 第$startPeriod 节'),
      );

  test('5 列、6 个节次锚点', () {
    expect(
      parsed.columns.map((WeekdayColumn c) => c.weekday).toList(),
      <int>[1, 2, 3, 4, 5],
    );
    expect(
      parsed.periodAnchors.map((PeriodAnchor a) => a.period).toList(),
      <int>[1, 2, 3, 4, 5, 6],
    );
  });

  test('★ 左栏假节次行不影响节次范围（像素 pitch 被污染也修得回来）', () {
    // 周一文字左边缘压在列边界左边 → 像素会多认出 3~4 行假节次行。
    // 不按 OCR 锚点校正的话，pitch 会从 150 掉到 115，节次号整体偏。
    expect(cell(1, 1).endPeriod, 3);
    expect(cell(1, 4).startPeriod, 4);
    expect(cell(1, 4).endPeriod, 6);
  });

  test('★ 贴死、同色、间隙大的两块：按文字间隙切，节次各归各的', () {
    expect(cell(2, 1).endPeriod, 2);
    expect(cell(2, 4).startPeriod, 4);
    expect(cell(2, 4).endPeriod, 6);
    expect(cell(2, 1).name, '枫林课');
    expect(cell(2, 1).location, '枫林楼101');
    expect(cell(2, 4).name, '紫荆课');
    expect(cell(2, 4).location, '紫荆楼202');
  });

  test('★ 间隙小但底色变了：按底色变化线切（光看间隙会漏）', () {
    // 周三两块之间的文字间隙只有 80px（0.53 个节距），
    // 比"单门课课名到教室"的间隙大不了多少 —— 但底色从红变蓝
    expect(cell(3, 1).endPeriod, 1);
    expect(cell(3, 2).startPeriod, 2);
    expect(cell(3, 2).endPeriod, 6);
  });

  test('★ 同色 + 小间隙不能切：单门课不能被拆成两格', () {
    expect(cell(4, 1).endPeriod, 6);
    expect(parsed.cells.where((ParsedCell c) => c.weekday == 4).length, 1);
  });

  test('★ 块底边严格界定末节：下一节的节次行贴在底边下面就不算进来', () {
    // 周五的块底边在 1020，第 6 节行中心在 1050 —— 只差 30px，
    // 加容差（0.3×150=45）就会多算一节
    expect(cell(5, 1).endPeriod, 5);
  });

  test('日期行的光秃秃日号不混进课名', () {
    for (final ParsedCell c in parsed.cells) {
      expect(c.name, isNot(startsWith('1')));
      expect(c.name, isNot(startsWith('2')));
    }
    expect(cell(1, 1).name, '枫林课');
  });

  test('底部导航丢掉', () {
    expect(parsed.navDropped, contains('首页'));
  });

  mainSameName();
  mainRoomSpan();
  mainBareHeader();
  mainAnchorNoise();
}

// ===========================================================================
// 同名的两节课挨在一起
// ===========================================================================

/// 用户 2026-10-08 报的：**同一个名字的课程分成两节连在一起，只识别成一节课**。
///
/// 为什么难：同名 → App 给同一个底色 → "底色变化线"这个信号**直接失效**；
/// 课名/教室长的话，两节课之间的文字间隙还会被挤到 0.3 个节距以下
/// （不到 0.75 个节距就切不动）。只剩一条路：**教室行后面跟着课名行** ——
/// 这个 App 每个课块都是「课名行… + 教室行」，教室行总在最后，
/// 所以「教室行 → 非教室行」就是课与课的分界。
///
/// 下面这个夹具把两个信号都掐掉了：整块**一个底色**、间隙只有 0.3 个节距
/// —— 只有结构信号能分开。掐掉结构信号的话这里会并成一格。
final List<OcrBlock> sameNameFixture = <OcrBlock>[
  b(180, 180, 240, 210, '周一'),
  b(360, 180, 420, 210, '周二'),
  b(540, 180, 600, 210, '周三'),
  b(720, 180, 780, 210, '周四'),
  b(900, 180, 960, 210, '周五'),
  b(200, 240, 220, 260, '1'),
  b(380, 240, 400, 260, '2'),
  b(560, 240, 580, 260, '3'),
  b(740, 240, 760, 260, '4'),
  b(920, 240, 940, 260, '5'),
  for (int i = 0; i < 4; i++)
    b(16, 300.0 + i * 150 - 14, 50, 300.0 + i * 150 + 14, '${i + 1}'),
  // 第一节课：课名两行（枫林课 / 程）+ 教室两行（枫林楼 / 101）
  b(112, 290, 250, 320, '枫林课'),
  b(112, 330, 250, 360, '程'),
  b(150, 370, 280, 400, '枫林楼'),
  b(150, 410, 280, 440, '101'),
  // 第二节课：**同名同教室**，只隔 12px（0.08 个节距 —— 贴得几乎挨上）
  b(112, 452, 250, 482, '枫林课'),
  b(112, 492, 250, 522, '程'),
  b(150, 532, 280, 562, '枫林楼'),
  b(150, 572, 280, 602, '101'),
  b(400, 1120, 600, 1150, '首页'),
];

TimetablePixels buildSameNamePixels() {
  const int w = 1000, h = 1200;
  final Uint8List px = Uint8List(w * h * 4);
  for (int i = 0; i < w * h; i++) {
    px[i * 4] = 255;
    px[i * 4 + 1] = 255;
    px[i * 4 + 2] = 255;
    px[i * 4 + 3] = 255;
  }
  void rect(double l, double t, double r, double bo, int rr, int gg, int bb) {
    for (int y = t.round(); y <= bo.round() && y < h; y++) {
      for (int x = l.round(); x <= r.round() && x < w; x++) {
        final int p = (y * w + x) * 4;
        px[p] = rr;
        px[p + 1] = gg;
        px[p + 2] = bb;
      }
    }
  }

  for (int i = 0; i < 4; i++) {
    final double y = 300.0 + i * 150;
    rect(16, y - 14, 50, y + 14, 70, 70, 70);
  }
  // ⚠️ 整块**一个底色**：同名的两节课在真图上就是这个样子（App 按课名配色），
  // 所以"底色变化线"信号在这里必须失效
  rect(120, 280, 300, 880, 235, 195, 130);
  for (final OcrBlock blk in sameNameFixture) {
    if (blk.top < 280 || blk.top > 800) continue;
    final double wPart = (blk.right - blk.left) * 0.18;
    rect(blk.left, blk.top + 6, blk.left + wPart, blk.bottom - 6, 40, 40, 40);
  }
  return TimetablePixels(width: w, height: h, rgba: px);
}

void mainSameName() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ParsedTimetable parsed;

  setUpAll(() {
    parsed = parseTimetable(sameNameFixture, pixels: buildSameNamePixels());
  });

  test('★ 同名 + 同色 + 小间隙：靠「教室行→课名行」切成两格', () {
    final List<ParsedCell> cells =
        parsed.cells.where((ParsedCell c) => c.weekday == 1).toList()
          ..sort((ParsedCell a, ParsedCell b) =>
              (a.startPeriod ?? 0).compareTo(b.startPeriod ?? 0));
    expect(cells.length, 2, reason: '同名的两节课不能并成一格');
    expect(cells[0].name, '枫林课程');
    expect(cells[0].location, '枫林楼101');
    expect(cells[1].name, '枫林课程');
    expect(cells[1].location, '枫林楼101');
    expect(cells[0].endPeriod, lessThan(cells[1].startPeriod ?? 0));
  });
}

// ===========================================================================
// 教室名跨行（课名/教室的边界）
// ===========================================================================

/// 用户 2026-10-08 报的「**上课地点识别的不正确**」。
///
/// 真图上教室名 `东苑综合楼…` 会被 OCR 拆成 `东苑综` + `台楼…` 两行，
/// 而 `东苑综` 单独**不含 楼/室/场/馆/房/敦/教、也不含数字** ——
/// 教室行判据认不出来，于是被算进课名（真图周4 7-8 的课名成了
/// `…(Python...东苑综`，地点只剩 `台楼...`）。
///
/// 修法：强规则找到教室行后**往上看一行** —— 纯汉字、3~4 字、
/// 且课名还剩 ≥ 4 字，就也算教室。
///
/// 夹具同时钉住**反向保护**：课名尾行（`技术境`，3 字纯汉字）不能被吃进
/// 教室 —— 它上面只剩 `智慧课`（3 字），去掉课名就碎了。
final List<OcrBlock> roomSpanFixture = <OcrBlock>[
  b(180, 180, 240, 210, '周一'),
  b(360, 180, 420, 210, '周二'),
  b(540, 180, 600, 210, '周三'),
  b(720, 180, 780, 210, '周四'),
  b(900, 180, 960, 210, '周五'),
  b(200, 240, 220, 260, '1'),
  for (int i = 0; i < kPeriods; i++)
    b(16, kPeriodY[i] - 14, 50, kPeriodY[i] + 14, '${i + 1}'),
  // 周一：课名 1 行 + 教室 2 行（第一行是碎片，判据认不出是教室）
  b(112, 290, 250, 320, '枫林课程设计'),
  b(150, 330, 280, 360, '紫荆综'),
  b(150, 370, 280, 400, '合楼202'),
  // 周二：课名 2 行，尾行是 3 字纯汉字 —— **不能**被吃进教室
  b(305, 290, 440, 320, '智慧课'),
  b(305, 330, 440, 360, '技术境'),
  b(340, 370, 470, 400, '场馆101'),
];

TimetablePixels buildRoomSpanPixels() {
  const int w = 1000, h = 1200;
  final Uint8List px = Uint8List(w * h * 4);
  void fill(int r, int g, int bl) {
    for (int i = 0; i < w * h; i++) {
      px[i * 4] = r;
      px[i * 4 + 1] = g;
      px[i * 4 + 2] = bl;
      px[i * 4 + 3] = 255;
    }
  }

  void rect(double l, double t, double r, double bo, int rr, int gg, int bb) {
    for (int y = t.round(); y <= bo.round() && y < h; y++) {
      for (int x = l.round(); x <= r.round() && x < w; x++) {
        final int p = (y * w + x) * 4;
        px[p] = rr;
        px[p + 1] = gg;
        px[p + 2] = bb;
      }
    }
  }

  fill(255, 255, 255);
  for (final double y in kPeriodY) {
    rect(16, y - 14, 50, y + 14, 70, 70, 70);
  }
  rect(120, 280, 300, 680, 240, 200, 200);
  rect(300, 280, 480, 680, 200, 230, 200);
  for (final OcrBlock blk in roomSpanFixture) {
    if (blk.top < 280 || blk.top > 1000) continue;
    final double wPart = (blk.right - blk.left) * 0.18;
    rect(blk.left, blk.top + 6, blk.left + wPart, blk.bottom - 6, 40, 40, 40);
  }
  return TimetablePixels(width: w, height: h, rgba: px);
}

void mainRoomSpan() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ParsedTimetable parsed;

  setUpAll(() {
    parsed = parseTimetable(roomSpanFixture, pixels: buildRoomSpanPixels());
  });

  ParsedCell cell(int weekday, int startPeriod) => parsed.cells.firstWhere(
        (ParsedCell c) =>
            c.weekday == weekday && c.startPeriod == startPeriod,
        orElse: () => throw StateError('没有 周$weekday 第$startPeriod 节'),
      );

  test('★ 教室名跨行：碎片行归教室，不混进课名', () {
    expect(cell(1, 1).name, '枫林课程设计');
    expect(cell(1, 1).location, '紫荆综合楼202');
  });

  test('★ 反向保护：课名尾行（3 字纯汉字）不能被吃进教室', () {
    expect(cell(2, 1).name, '智慧课技术境');
    expect(cell(2, 1).location, '场馆101');
  });
}

// ===========================================================================
// 裸表头（没有「周」字）+ 标签被粘成一块
// ===========================================================================

/// 用户 2026-10-08 深夜报的：「**表头没有『周』字就识别不出来了**」。
///
/// 真机实测（ML Kit）：
///   - 表头写的是**裸的** `一 二 三 四 五 六 日`，一个「周」字都没有 ——
///     `^周X` 那条锚定全部落空，只能走裸表头兜底
///   - 更糟的是「一」「二」是细横线字形，**被整块漏读**，剩下的
///     `三 四 五 六` **粘成一个块**（4 个字）
///   - 日期行里 `11/4 11/5` 也粘成一个块
///
/// 兜底原来卡了 `dense.length > 3`（历史样本只粘 2 个字），于是整行表头
/// 被跳过、只剩孤零零一个 `日`，兜底直接放弃 → 报"没找到星期表头"。
/// 修法：长度上限放到 **7**（一周最多 7 天），反正「尾巴还有汉字就跳过」
/// 那条已经能挡住 `三教` 这类正文。
final List<OcrBlock> bareHeaderFixture = <OcrBlock>[
  // 表头：无「周」字，且「一」「二」漏读、`三四五六` 粘成一块
  b(430, 180, 900, 210, '三四五六'),
  b(990, 180, 1030, 210, '日'),
  // 日期行：`11/4 11/5` 粘成一块
  b(170, 240, 206, 260, '11/2'),
  b(307, 240, 343, 260, '11/3'),
  b(444, 240, 516, 260, '11/4 11/5'),
  b(718, 240, 754, 260, '11/6'),
  b(855, 240, 891, 260, '11/7'),
  b(992, 240, 1028, 260, '11/8'),
  // 节次栏
  for (int i = 0; i < kPeriods; i++)
    b(16, kPeriodY[i] - 14, 50, kPeriodY[i] + 14, '${i + 1}'),
  // 一门课（周三）
  b(444, 290, 580, 320, '枫林课'),
  b(480, 330, 610, 360, '枫林楼101'),
];

void mainBareHeader() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ParsedTimetable parsed;

  setUpAll(() {
    parsed = parseTimetable(bareHeaderFixture);
  });

  test('★ 裸表头 + 标签粘连：仍然认出 7 列', () {
    expect(
      parsed.columns.map((WeekdayColumn c) => c.weekday).toList(),
      <int>[1, 2, 3, 4, 5, 6, 7],
      reason: '「一」「二」漏读、`三四五六` 粘成一块时，靠日期行定位置、'
          '靠认得出的标签定身份，必须把 7 列补齐',
    );
  });

  test('★ 表头文字没被当成课名/教室', () {
    for (final ParsedCell c in parsed.cells) {
      final String n = c.name ?? '';
      expect(n.contains('三四五六'), isFalse);
      expect(n.contains('11/'), isFalse);
    }
  });
}

// ===========================================================================
// 节次锚点：表头区的数字 / 贴太近的噪声数字
// ===========================================================================

/// 用户 2026-10-09 报的「课表导入只能识别到四节课」（实际是 13 门课只剩 7 格）。
///
/// 真机实测两个**假锚点**把节次链搞乱了：
///
///   1. **表头的 `10`**：这款 App 把月份单独写一行 `10月`，OCR 把它拆成
///      `10` + `2月` —— 那个 `10` 落在节次栏的 x 范围里，被当成「第 10 节」。
///   2. **节次 1 和 2 之间凭空冒出的 `7`**：两者只差 69px，而正常间距是 240。
///
/// 后果：收编逻辑把**真节次 2 丢掉**，最后按位置重编号 → **所有节次号整体 +1**
/// （第 1-2 节的课被识别成 2-3 节）。
final List<OcrBlock> anchorNoiseFixture = <OcrBlock>[
  // 表头（裸的 `一 二 三 四 五 六 日`）+ 月份被拆出来的 `10`
  b(430, 180, 900, 210, '三四五六'),
  b(990, 180, 1030, 210, '日'),
  b(55, 180, 93, 210, '10'), // ⚠️ 「10月」的一半，落在节次栏 x 范围
  b(170, 240, 206, 260, '12'),
  b(307, 240, 343, 260, '13'),
  b(444, 240, 516, 260, '14 15'),
  b(718, 240, 754, 260, '16'),
  b(855, 240, 891, 260, '17'),
  b(992, 240, 1028, 260, '18'),
  // 节次栏：1 2 3 …，但 1 和 2 之间混进一个误认的 `7`
  b(16, kPeriodY[0] - 14, 50, kPeriodY[0] + 14, '1'),
  b(16, kPeriodY[0] + 40, 50, kPeriodY[0] + 68, '7'), // ⚠️ 噪声：离上一锚点只有 54px
  b(16, kPeriodY[1] - 14, 50, kPeriodY[1] + 14, '2'),
  b(16, kPeriodY[2] - 14, 50, kPeriodY[2] + 14, '3'),
  b(16, kPeriodY[3] - 14, 50, kPeriodY[3] + 14, '4'),
  // 第一节课（第 1 节）—— 修好后应该落在 1，不是 2
  b(112, kPeriodY[0] - 10, 250, kPeriodY[0] + 20, '丁香课'),
  b(150, kPeriodY[0] + 30, 280, kPeriodY[0] + 60, '丁香楼101'),
];

void mainAnchorNoise() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ParsedTimetable parsed;

  setUpAll(() {
    parsed = parseTimetable(anchorNoiseFixture);
  });

  test('★ 表头区的数字 + 贴太近的噪声数字都不能当节次锚点', () {
    expect(
      parsed.periodAnchors.map((PeriodAnchor a) => a.period).toList(),
      <int>[1, 2, 3, 4],
      reason: '假锚点（表头的 `10`、节次 1-2 之间的 `7`）不能进锚点链，'
          '否则真节次会被挤掉、整列节次号偏移',
    );
  });

  test('★ 第 1 节的课不能被识别成第 2 节', () {
    expect(parsed.cells, isNotEmpty, reason: '夹具至少要能解析出一格');
    // 假锚点会让所有节次号整体 +1，所以最靠上的那格必然从 2 开始
    final List<int> starts = parsed.cells
        .map((ParsedCell c) => c.startPeriod)
        .whereType<int>()
        .toList();
    expect(starts, isNotEmpty, reason: '每格都应该有节次');
    expect(starts.reduce((int a, int b) => a < b ? a : b), 1,
        reason: '假锚点会让所有节次号整体 +1（第 1 节变成第 2 节）');
  });
}
