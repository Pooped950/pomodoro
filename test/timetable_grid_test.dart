import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/ocr/ocr_result.dart';
import 'package:pomodoro/domain/ocr/timetable_grid.dart';
import 'package:pomodoro/domain/timetable/period_time.dart';

/// 课表版面解析的回归测试。
///
/// 坐标全部来自 **2026-10-06 真实课表截图** 的 ML Kit 识别输出
/// （小米 17 Pro Max，某校园课表 App），文本替换成了合成课程名 ——
/// 几何结构（列位置、行距、合并行、噪声）与真实数据完全一致，
/// 所以对解析规则的验证价值相同，又不把真实课表内容带进仓库。
OcrBlock b(double l, double t, double r, double bo, String text) =>
    OcrBlock(text: text, left: l, top: t, right: r, bottom: bo);

/// 与真实 dump 同构的输入（见 docs 排查记录：78 行那次的几何骨架）
final List<OcrBlock> fixture = <OcrBlock>[
  // 顶部（表头以上，应被丢弃）
  b(76, 47, 145, 72, '15:51'),
  b(38, 149, 208, 189, '某某查询'),
  b(252, 358, 665, 393, '2026-2027学年第1学期'),
  b(401, 409, 520, 440, '第6周v'),
  // 星期表头（「周三 周四」是 OCR 合并行）
  b(83, 483, 133, 506, '周一'),
  b(202, 483, 252, 506, '周二'),
  b(322, 483, 490, 507, '周三 周四'),
  b(560, 483, 608, 506, '周五'),
  b(669, 480, 739, 508, '周六'),
  b(799, 483, 846, 506, '周日'),
  // 日期行（两处合并）
  b(75, 526, 261, 546, '10-12 10-13'),
  b(312, 523, 380, 546, '10-14'),
  b(433, 526, 500, 546, '10-15'),
  b(552, 526, 738, 546, '10-16 10-17'),
  b(791, 526, 858, 546, '10-18'),
  // 周一：一个跨 1-2 节的大格（课程/节次/教室多行）
  b(70, 591, 145, 616, '材料力学'),
  b(69, 624, 140, 655, '(一)'),
  b(56, 676, 158, 699, '1问渠楼修远'),
  // 跨列合并行（周一+周二连成一行）
  b(67, 701, 388, 728, '问渠楼量子光学问渠楼'),
  b(70, 730, 258, 758, '307教室 |A(一)'),
  // 周三：同样的大格
  b(309, 591, 383, 616, '结构力学'),
  b(309, 624, 378, 655, '(二)'),
  b(294, 678, 398, 699, '|问渠楼修远'),
  b(308, 732, 383, 753, '307教室'),
  // 节次栏（1-6 是干净的孤立数字；7 与课程文字被 OCR 粘连）
  b(22, 617, 27, 635, '1'),
  b(19, 747, 30, 765, '2'),
  b(19, 877, 29, 894, '3'),
  b(19, 983, 31, 999, '4'),
  b(19, 1089, 30, 1106, '5'),
  b(19, 1195, 28, 1211, '6'),
  // 周四：两个相邻但独立的格（间距 58px，超过聚格阈值）
  b(414, 849, 515, 877, '|流体力学'),
  b(414, 935, 513, 959, '云浦三教'),
  b(414, 966, 516, 986, '|云浦三教'),
  b(429, 993, 502, 1013, '210教室'),
  // 周五：一个长格
  b(534, 592, 635, 616, '|结构力学'),
  b(560, 627, 609, 651, '|基础'),
  b(533, 679, 637, 698, '云浦四教!'),
  b(536, 706, 641, 726, '(实训楼)云'),
  b(543, 733, 625, 754, '杉浦四教'),
  b(546, 763, 621, 782, '(实训楼)'),
  b(546, 788, 623, 810, '|202教室'),
  // 周五：靠下的另一个独立格（与前格间距 723px）
  b(533, 1533, 635, 1559, '|工程制图'),
  b(560, 1571, 609, 1595, '|基础'),
  b(533, 1622, 637, 1642, '|云浦一教'),
  b(536, 1650, 642, 1670, '|(明月楼)云'),
  b(534, 1705, 628, 1729, '|(明月楼)'),
  // 周二：粘在节次栏上的粘连行（会变成一个独立小格 —— 已知行为）
  b(15, 1306, 154, 1337, '7问渠..教'),
  b(176, 784, 279, 805, '|问渠楼修远'),
  b(186, 810, 266, 832, '问渠楼'),
  b(189, 839, 265, 860, '307教室'),
  // 底部噪声：悬浮球数字 + 导航
  b(603, 1783, 637, 1807, '100'),
  b(431, 1798, 456, 1826, '十'),
  b(64, 1833, 110, 1856, '首页'),
  b(241, 1833, 288, 1855, '课表'),
  b(594, 1833, 642, 1856, '成绩'),
  b(771, 1833, 818, 1855, '我的'),
];

void main() {
  late ParsedTimetable parsed;

  setUpAll(() {
    parsed = parseTimetable(fixture);
  });

  test('识别出 7 列，星期按周一～周日排序', () {
    expect(parsed.columns.map((WeekdayColumn c) => c.weekday).toList(),
        <int>[1, 2, 3, 4, 5, 6, 7]);
  });

  test('「周三 周四」合并行被正确拆成两列', () {
    // 合并行 [322,490] 两段等宽：周三 [322-406]、周四 [406-490]
    expect(parsed.columns[2].centerX, closeTo(364, 1));
    expect(parsed.columns[3].centerX, closeTo(448, 1));
  });

  test('日期按列归位（合并行的多个日期也各归各列）', () {
    expect(parsed.columns[0].date, '10-12');
    expect(parsed.columns[1].date, '10-13');
    expect(parsed.columns[2].date, '10-14');
    expect(parsed.columns[3].date, '10-15');
    expect(parsed.columns[4].date, '10-16');
    expect(parsed.columns[5].date, '10-17');
    expect(parsed.columns[6].date, '10-18');
  });

  test('同一格的多行文本聚在一起，格与格按间距切开', () {
    // 周四大格：流体力学（849-877）与 云浦三教（935 起）间距 58，应切开
    final List<ParsedCell> thu =
        parsed.cells.where((ParsedCell c) => c.weekday == 4).toList();
    expect(thu.length, 2);
    expect(thu[0].courseNameGuess, '流体力学'); // 行首竖线是 OCR 噪声，猜测值里要去掉
    expect(thu[1].lines.length, 3);
    expect(thu[1].locationGuess, '210教室');
  });

  test('周五长格跨 1-2 节（节次由左侧栏反推）', () {
    final List<ParsedCell> fri =
        parsed.cells.where((ParsedCell c) => c.weekday == 5).toList()
          ..sort((ParsedCell a, ParsedCell b) => a.top.compareTo(b.top));
    // 第一个格：1-2 节的七行长格；第二个格：靠下的独立格
    expect(fri.length, 2);
    expect(fri[0].startPeriod, 1);
    expect(fri[0].endPeriod, 2);
    expect(fri[0].lines.length, 7);
  });

  test('跨列合并行被打上 spanningSuspicion 标记', () {
    // 跨列行按中心归列（落进了周二），但内容横跨了周一+周二两列 ——
    // v1 策略：按中心归列 + 打标，交给预览页让用户改
    final ParsedCell spanned = parsed.cells.singleWhere(
        (ParsedCell c) => c.lines.contains('问渠楼量子光学问渠楼'));
    expect(spanned.spanningSuspicion, isTrue);
  });

  test('导航 / 悬浮球 / 表头以上内容全部被丢弃', () {
    for (final String noise in <String>['首页', '课表', '成绩', '我的', '100', '十']) {
      expect(parsed.navDropped, contains(noise), reason: '$noise 应被丢弃');
    }
    // 顶部内容不应变成任何课程格
    for (final ParsedCell c in parsed.cells) {
      expect(c.courseNameGuess, isNot('15:51'));
      expect(c.courseNameGuess, isNot('某某查询'));
      expect(c.courseNameGuess, isNot('2026-2027学年第1学期'));
      expect(c.courseNameGuess, isNot('第6周v'));
    }
  });

  test('节次栏数字本身不进课程格', () {
    for (final ParsedCell c in parsed.cells) {
      for (final String line in c.lines) {
        expect(RegExp(r'^\d{1,2}$').hasMatch(line), isFalse,
            reason: '节次数字 $line 混进了课程格');
      }
    }
  });

  test('不是课表的输入要给出可读的错误', () {
    expect(() => parseTimetable(<OcrBlock>[b(0, 0, 10, 10, '你好')]),
        throwsA(isA<TimetableParseException>()));
  });

  group('OCR 脏输入：表头竖线 + 两位数读残', dirtyTests);
}

// ===========================================================================
// 2026-10-07 那次真实 bug 的回归
// ===========================================================================

/// 2026-10-07 真机实测那次的几何骨架（坐标取自真实 OCR dump，
/// 文本换成合成课程名）。两个噪声凑在一起，一个让**整列消失**、
/// 一个让**午休判定跑偏**：
///
///   1. 表头那行 OCR 吐的是 `|周二` —— 行首粘了表格竖线
///   2. 节次栏最后一节的 `13` 被读成了 `1`（块高只有 32px，挤成了单字符）
///
/// 症状（用户原话）：**"课程挤在最上面了没有平铺成表格形式，而且周日没有课
/// 却识别到了课程"**。链路是：
///   `|周二` 匹配失败 → 周二列消失 → 周一列宽被撑成两倍 → 节次栏落进"课程区"
///   被当噪声丢掉 → 0 个节次 → 时间表排不出来 → 只剩一行；
///   同时周二的内容按"最近的列"兜底，全被塞进最右边的周日。
final List<OcrBlock> dirtyFixture = <OcrBlock>[
  // 表头以上的内容（应被丢弃）
  b(342, 485, 904, 535, '2026-2027学年第1学期'),
  b(526, 551, 717, 599, '第5周v'),
  // 星期表头 —— 注意周二这行的行首竖线
  b(95, 654, 190, 689, '周一'),
  b(275, 657, 342, 687, '|周二'),
  b(437, 657, 505, 686, '周三'),
  b(599, 657, 665, 688, '周四'),
  b(761, 657, 828, 687, '周五'),
  b(923, 655, 991, 687, '周六'),
  b(1085, 657, 1149, 687, '周日'),
  // 日期行（中间四个被并成了一行）
  b(99, 715, 194, 742, '10-05'),
  b(261, 715, 842, 742, '10-06 10-07 10-08 10-09'),
  b(912, 715, 1002, 742, '10-10'),
  b(1077, 715, 1160, 742, '10-11'),
  // 节次栏 1~12：第 7 节 OCR 整个漏了，最后一节的 13 被读成 1
  b(29, 838, 37, 859, '1'),
  b(26, 1015, 40, 1039, '2'),
  b(26, 1191, 41, 1215, '3'),
  b(26, 1335, 41, 1359, '4'),
  b(26, 1479, 41, 1503, '5'),
  b(26, 1623, 41, 1647, '6'),
  b(25, 1960, 40, 1984, '8'),
  b(26, 2155, 42, 2179, '9'),
  b(19, 2370, 46, 2394, '10'),
  b(22, 2549, 44, 2570, '11'),
  b(20, 2693, 47, 2717, '12'),
  b(16, 2830, 38, 2862, '1'), // 其实是第 13 节
  // 周一第 1 节（三行一个格）
  b(95, 804, 195, 837, '甲课'),
  b(118, 853, 172, 885, '(一)'),
  b(77, 921, 218, 949, '一号楼 101'),
  // 周二第 2-3 节 —— 这一格绝不能被判成周日
  b(253, 1100, 359, 1130, '乙课'),
  b(243, 1136, 367, 1169, '二号楼 202'),
  // 底部噪声
  b(820, 2968, 864, 2991, '100'),
  b(87, 3036, 148, 3067, '首页'),
  b(327, 3036, 389, 3066, '课表'),
  b(807, 3036, 870, 3067, '成绩'),
  b(1047, 3036, 1111, 3066, '我的'),
];

void dirtyTests() {
  late ParsedTimetable parsed;

  setUpAll(() {
    parsed = parseTimetable(dirtyFixture);
  });

  test('★ 表头行首粘了竖线（`|周二`）也要认出这一列', () {
    expect(
      parsed.columns.map((WeekdayColumn c) => c.weekday).toList(),
      <int>[1, 2, 3, 4, 5, 6, 7],
      reason: '少一列，整张表都会歪',
    );
    expect(parsed.columns[1].centerX, closeTo(308.5, 1));
  });

  test('★ 周二的内容不会被兜底塞进周日', () {
    expect(
      parsed.cells.where((ParsedCell c) => c.weekday == 7),
      isEmpty,
      reason: '周日一节课都没有 —— 用户报的"周日凭空多出课程"就是这里',
    );
    final ParsedCell tue =
        parsed.cells.singleWhere((ParsedCell c) => c.weekday == 2);
    expect(tue.courseNameGuess, '乙课');
  });

  test('★ 节次栏不被"课程区"吞掉（课程挤在最上面的根因）', () {
    // 周二列缺位时，周一列的归列边界会被撑到 left≈-22，
    // 节次栏的 1~13 就落进了课程区、被当噪声丢掉 → 0 个节次
    expect(parsed.columns.first.left, greaterThan(40),
        reason: '第一列的左边界必须在节次栏右边');
    expect(parsed.periodAnchors, isNotEmpty, reason: '0 个节次 = 时间表排不出来');
  });

  test('★ 漏读的第 7 节补幽灵锚点，读残的 13 按位置收编 —— 节次号连续', () {
    // 2026-10-07 之前的行为是把读残的 13 直接滤掉：13 节的课表只认出 11 个锚点，
    // 第 7 节之后所有课错位一格，排时间时课间被挤成 0（用户报的"课间没做出来"）。
    // 现在按物理位置补全：第 7 节整块漏读 → 间距翻倍处插幽灵锚点；
    // 末尾的 `1`（实为 13）y 正好落在下一节的位置 → 收编重编号。
    expect(
      parsed.periodAnchors.map((PeriodAnchor a) => a.period).toList(),
      <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
      reason: '节次号必须连续，后面课程的第几节才不会错位',
    );
  });

  test('★ 锚点顺序是物理位置顺序，幽灵锚点插在正中间', () {
    final List<double> ys = parsed.periodAnchors
        .map((PeriodAnchor a) => a.centerY)
        .toList();
    for (int i = 1; i < ys.length; i++) {
      expect(ys[i], greaterThan(ys[i - 1]), reason: '锚点必须自上而下排列');
    }
    // 第 7 节的幽灵锚点应该落在 6 和 8 的正中间（真实缺口的两个邻居）
    expect(ys[6], closeTo((ys[5] + ys[7]) / 2, 2));
    // ⚠️ 上午/下午的分界**不能**靠像素间隔猜：实测行距不均匀（144~216px），
    // 9→10 的间距可以比 6→7 还大。这个分界现在由用户在导入页给节数。
    expect(morningPeriodCountFromAnchors(ys), isNot(7),
        reason: '均匀行距里"最大间隔=午休"的假设不成立，只当兜底预填用');
  });

  test('★ 格的节次范围真的反推出来了（不再是 null）', () {
    final ParsedCell tue =
        parsed.cells.singleWhere((ParsedCell c) => c.weekday == 2);
    expect(tue.startPeriod, 2);
    expect(tue.endPeriod, 3);
  });

  test('带噪声的表头行不会掉进课程格', () {
    for (final ParsedCell c in parsed.cells) {
      for (final String line in c.lines) {
        expect(line.contains('周二'), isFalse, reason: '表头文字 "$line" 变成了课程');
      }
    }
  });

  test('日期行仍然按列归位', () {
    expect(parsed.columns.map((WeekdayColumn c) => c.date).toList(),
        <String>['10-05', '10-06', '10-07', '10-08', '10-09', '10-10', '10-11']);
  });
}
