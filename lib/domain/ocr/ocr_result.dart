import 'package:meta/meta.dart';

/// 一个**词/字级**的坐标（ML Kit 的 `TextElement`）。
///
/// ⚠️ 为什么必须留着（2026-10-10 真机实测发现）：
///
/// 跨列粘连行要按"每个字属于哪一列"来切分（见 `timetable_grid.dart` 的
/// `_splitSpanningLine`），而 [OcrBlock] 只有**整行**的 `left`/`right` ——
/// 以前只能按"平均字宽"估算每个字的位置。**一行里汉字和数字混排时
/// （数字只有汉字一半宽）估算必然偏**，切点跟着偏，前一列的尾巴就被
/// 切给了后一列。真机实测的后果：
///
/// ```
/// '室A(-)树达楼桃花坪树达楼307教室'   ← 开头 `室A(-)` 是别的格的尾巴
/// '1桃花坪一教(达善楼)A02A04…'        ← 开头多一个 `1`
/// ```
///
/// ML Kit **本来就**给了每个词的精确坐标，只是以前被丢掉了。
/// 留着它就能按真实位置切，不用估算。
@immutable
class OcrWord {
  const OcrWord({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get width => right - left;

  @override
  String toString() => 'OcrWord("$text" @${left.round()}-${right.round()})';
}

/// 一个被识别出来的文本行，**带坐标**。
///
/// 为什么必须保留坐标：课表识别的难点根本不在"认字"，而在
/// **"这个字属于哪一行、哪一列"**。没有位置信息，OCR 结果就是一坨
/// 顺序不可靠的文本，还原不出「节次 × 星期」的网格。
@immutable
class OcrBlock {
  const OcrBlock({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.words = const <OcrWord>[],
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// 行内每个词的精确坐标（见 [OcrWord]）。
  ///
  /// 可能为空：老的调用点（测试夹具、别处构造的 block）不传；
  /// 跨列拆分遇到空列表会自动退回"平均字宽估算"的老路。
  final List<OcrWord> words;

  double get centerY => (top + bottom) / 2;
  double get centerX => (left + right) / 2;
  double get height => bottom - top;
  double get width => right - left;

  @override
  String toString() => 'OcrBlock("$text" @${left.round()},${top.round()})';
}

/// 一次识别的完整结果
@immutable
class OcrResult {
  const OcrResult({required this.blocks, required this.rawText});

  /// 文本行（保留原始顺序，展示前请用 [inReadingOrder]）
  final List<OcrBlock> blocks;

  /// ML Kit 给的整段文本（换行已按它的版面判断拼好）
  final String rawText;

  /// 便于复制给我看的最小摘要
  String get debugDump {
    final StringBuffer sb = StringBuffer();
    for (final OcrBlock b in inReadingOrder(blocks)) {
      sb.writeln('[${b.left.round()},${b.top.round()}-'
          '${b.right.round()},${b.bottom.round()}] ${b.text}');
    }
    return sb.toString();
  }
}

/// 按**阅读顺序**排：从上到下、同一行内从左到右。
///
/// 纯函数，宿主机可直接单测。
///
/// 关键在"同一行"的判定 —— 不能要求 top 完全相等（同一行的字块
/// 上下会差几个像素），所以用 [rowTolerance] 做容差：两个块的中心线
/// 差距在容差内就算同一行。
///
/// 容差默认取「所有块高度中位数的一半」—— 比写死一个像素值稳，
/// 因为不同截图的分辨率差别很大（1080 宽和 2400 宽差一倍多）。
List<OcrBlock> inReadingOrder(
  List<OcrBlock> blocks, {
  double? rowTolerance,
}) {
  if (blocks.isEmpty) return const <OcrBlock>[];

  final double tolerance = rowTolerance ?? _medianHeight(blocks) / 2;

  final List<OcrBlock> sorted = List<OcrBlock>.of(blocks)
    ..sort((OcrBlock a, OcrBlock b) {
      final int byTop = a.centerY.compareTo(b.centerY);
      if (byTop != 0) return byTop;
      return a.centerX.compareTo(b.centerX);
    });

  // 再把"中心线足够接近"的相邻块归为一行，行内按 x 排
  final List<OcrBlock> out = <OcrBlock>[];
  int i = 0;
  while (i < sorted.length) {
    final double rowY = sorted[i].centerY;
    final List<OcrBlock> row = <OcrBlock>[];
    while (i < sorted.length &&
        (sorted[i].centerY - rowY).abs() <= tolerance) {
      row.add(sorted[i]);
      i++;
    }
    row.sort((OcrBlock a, OcrBlock b) => a.left.compareTo(b.left));
    out.addAll(row);
  }
  return out;
}

double _medianHeight(List<OcrBlock> blocks) {
  final List<double> heights =
      blocks.map((OcrBlock b) => b.height).toList()..sort();
  final double h = heights[heights.length ~/ 2];
  return h <= 0 ? 1 : h;
}
