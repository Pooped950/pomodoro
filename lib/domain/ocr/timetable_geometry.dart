import 'dart:typed_data';
import 'package:meta/meta.dart';

/// 从拼图**像素**里量出来的课表几何 —— 课程块的行列骨架。
///
/// ## 为什么需要像素，光靠 OCR 文字不行（2026-10-07 真图实测）
///
/// 校园课表 App 的课程块是「文字挤在块顶、下面大片留白」：
/// 周四那节跨 7-10 节的高数，文字只占第 7 节那一小条，下面空着两行半。
/// 光看文字的 y 范围只能推出 7-8，**推不出 7-10** —— 只有色块本身的
/// 上下边缘才知道这格课真实跨到哪。另外相邻两块课的缝隙可以只有 2px
/// （周五 7-8 和 9-10 两块蓝色几乎贴死），纯文字间距聚格永远分不开。
///
/// 所以：**几何（第几列、第几节到第几节）量自像素，文字（课名教室）来自
/// OCR**，两层各用各的长处。
///
/// ## 纯函数
///
/// 输入就是一坨 RGBA 字节 + 几个从 OCR 已经算出来的参数，
/// 宿主机（flutter test）可以直接喂合成图跑单测，不用真机。
@immutable
class TimetableGeometry {
  const TimetableGeometry({
    required this.labelCentersY,
    required this.blocks,
  });

  /// 节次行的纵向中心（像素，升序）。第 1 个 = 第 1 节。
  ///
  /// ⚠️ 实测行距**不均匀**（144~216px 都有），别拿均匀行距做假设。
  final List<double> labelCentersY;

  /// 课程色块（已按「左→右、上→下」排序）
  final List<GeometryBlock> blocks;

  int get periodCount => labelCentersY.length;

  /// 各节次中心间距的中位数 —— 判「块里含不含某个节次」的容差基准
  double get medianPitch {
    if (labelCentersY.length < 2) return 100;
    final List<double> gaps = <double>[
      for (int i = 1; i < labelCentersY.length; i++)
        labelCentersY[i] - labelCentersY[i - 1],
    ]..sort();
    return gaps[gaps.length ~/ 2];
  }

  /// 像素块 [block] 覆盖了哪些节次（1 起）。
  ///
  /// 判据是「节次中心落在块内」而不是「离哪节最近」—— 跨 4 节的大块
  /// 上下沿离首尾节次很远，按最近算会把 7-10 算成 6-11（实测栽过）。
  /// [tolerance] 给 OCR/测边留一点余量。
  List<int> periodsCovering(GeometryBlock block, {double? tolerance}) {
    final double tol = tolerance ?? medianPitch * 0.3;
    final List<int> hit = <int>[
      for (int i = 0; i < labelCentersY.length; i++)
        if (labelCentersY[i] >= block.top - tol &&
            labelCentersY[i] <= block.bottom + tol)
          i + 1,
    ];
    if (hit.isNotEmpty) return hit;
    // 块太小、一个节次中心都没罩住（识别残块）：退回「离哪节最近」
    final double cy = (block.top + block.bottom) / 2;
    int best = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < labelCentersY.length; i++) {
      final double d = (labelCentersY[i] - cy).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return <int>[best + 1];
  }

  /// 用 OCR 认出来的**节次锚点**校正像素量出的节次行。
  ///
  /// ## 为什么必须校正（2026-10-08 真图实测）
  ///
  /// 像素扫描把「左栏的暗色簇」当节次行，在真实课表上会出两类错：
  ///
  ///   - **假节次行**：课程列的文字左边缘比列边界还靠左（列边界是按粘成
  ///     一块的表头 `周一 周二` 按字符均分算出来的，实测偏右 ~15px），
  ///     于是每行课程文字最左边的十几像素落进「左栏」，被当成节次行 ——
  ///     实测 16 行里 **8 行是假的**
  ///   - **真节次行被粘连后整块丢掉**：假簇和真节次号挨在一起聚成一个
  ///     高 62px 的簇，超过 60px 的高度上限被丢弃 —— 11 个真节次行只剩 8 个
  ///
  /// 后果是 `medianPitch` 从 126 掉到 54，**每个块的节次范围全错**
  /// （周一跨 4 门课的一块被算成 1-11 节）。
  ///
  /// 节次号是**印在图上的数字**，OCR 认它比认像素簇可信。所以以锚点为准：
  /// 每个锚点吸附到容差内最近的像素标签，没有就退回锚点自身 ——
  /// 假簇被丢掉、漏掉的真行由锚点补上，行数正好等于节次数。
  ///
  /// ⚠️ 容差用**锚点自己的**间距中位数：像素标签的 pitch 正是被污染的。
  TimetableGeometry snapToAnchors(List<double> anchorCentersY) {
    if (anchorCentersY.length < 3 || labelCentersY.isEmpty) return this;
    final List<double> anchors = List<double>.of(anchorCentersY)..sort();
    final List<double> gaps = <double>[
      for (int i = 1; i < anchors.length; i++) anchors[i] - anchors[i - 1],
    ]..sort();
    final double pitch = gaps.isEmpty
        ? 100
        : gaps[gaps.length ~/ 2].clamp(20, 100000).toDouble();
    final double tol = pitch * 0.45;

    final List<double> out = <double>[];
    for (final double a in anchors) {
      double best = a;
      double bestDist = tol;
      for (final double y in labelCentersY) {
        final double d = (y - a).abs();
        if (d < bestDist) {
          bestDist = d;
          best = y;
        }
      }
      // 吸附后必须严格递增，否则节次号会反
      if (out.isNotEmpty && best <= out.last) best = a;
      if (out.isNotEmpty && best <= out.last) continue;
      out.add(best);
    }
    if (out.length < 2) return this;
    return TimetableGeometry(labelCentersY: out, blocks: blocks);
  }
}

/// 一节课列的 x 范围（从 OCR 星期表头算出来，原样传给扫描器）
@immutable
class GeometryBand {
  const GeometryBand({required this.left, required this.right});

  final double left;
  final double right;
}

/// 块内的一条**底色变化线**：[y] 是位置，[strength] 是两侧底色的最大通道差。
///
/// 强度越大越可信：真边界实测 10~18，文字抗锯齿蹭出来的假边界只有 8~10。
@immutable
class ColorEdge {
  const ColorEdge(this.y, this.strength);

  final double y;
  final int strength;

  @override
  String toString() => 'ColorEdge(${y.round()}, $strength)';
}

/// 一个课程色块（只有几何，没有文字）
@immutable
class GeometryBlock {
  const GeometryBlock({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.colorEdges = const <ColorEdge>[],
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  /// 块内**底色变化线**（按 y 升序）。
  ///
  /// 同一列相邻两门课**可以紧挨着没有白缝**，但 App 会给每门课一个底色，
  /// 所以底色变化处就是课与课的分界（实测：周一 粉`#fbe5e7`→米黄`#fef3df`→
  /// 浅黄`#ffffde`；周四 黄→粉→紫）。
  ///
  /// ⚠️ 只在块内相邻行之间找，**不是**把整列按色差切块 —— 那样会碎成
  /// 几十个小块（见 2026-10-07 的教训）。这里只输出"哪儿变色"，
  /// 由调用方决定要不要在文字间隙处用它当切点。
  final List<ColorEdge> colorEdges;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get width => right - left;
  double get height => bottom - top;
}

/// 节次栏标签的识别参数（都是从真图量出来的经验值，理由见各处注释）
abstract final class TimetableGeometryScanner {
  /// 「这是课程块的颜色」：饱和度（RGB 极差）超过它。
  ///
  /// ## ⚠️ 这个值必须按**最淡的一款配色**定（2026-10-07 真机实测）
  ///
  /// 一开始按另一款 App 的配色调成 30，结果换一款 App 就**只认出 1 个色块**、
  /// 整张课表只剩 1 格。采样真实像素后发现根因：
  ///
  /// | 像素 | 实测饱和度 |
  /// |---|---|
  /// | 白底 `#ffffff` / 网格线 `#f1f1f1` / 黑字 | **0 ~ 4** |
  /// | 课程块（淡黄 `#fafee5` / 淡紫 `#f6e4fc` / 淡绿 `#e8fdea`） | **21 ~ 30** |
  /// | 课程块（粉 `#ffd0cc` / 蓝 `#cae9fd`） | 40 ~ 104 |
  ///
  /// 也就是说：**底色越淡的 App，块和背景的差距越小**。30 这个值把
  /// 21~30 那一档全部误判成背景了。
  ///
  /// 取 12：非块像素实测上限是 4，留 3 倍余量；同时能覆盖 21 那一档。
  /// 换更淡的配色时这个值还要往下调 —— 判据的本质是"和背景有一点点色偏"，
  /// 不是"颜色鲜艳"。
  static const int _blockSaturation = 12;

  /// **强行**：块身行。白字行占不满横向跨度、悬浮箭头（蓝圆，只占
  /// 列宽 ~40%）不够格，只有块身能同时过这两关 —— 见扫描处的说明。
  static const double _strongFrac = 0.5;
  static const double _strongSpan = 0.75;

  /// **弱行**：块内文字行的下限（实测最糟 0.16），低于它开始数"断"
  static const double _weakFrac = 0.10;

  /// 色块最小高度（px）。太矮的不是课表块。
  static const double _minBlockHeight = 40;

  /// 「这是节次栏的文字」：亮度低于它且**不饱和**（灰黑色文字）。
  ///
  /// ⚠️ 亮度单条件不够：悬浮箭头是中饱和度的蓝，亮度也可能掉到 120 以下
  /// （实测 ≈125，贴着线），加上「RGB 差 < 60」把彩色的一律排除。
  static const int _labelLuminance = 120;
  static const int _labelSaturation = 60;

  /// 标签簇的合理高度范围（px）。太高的是把多行粘一起的噪声。
  static const double _labelMinHeight = 8;
  static const double _labelMaxHeight = 60;

  /// 扫描像素，量出节次行位置和课程块。
  ///
  /// [rgba] 为 length = width × height × 4 的 RGBA 字节；
  /// [bands] 是课程列的 x 范围（**从 OCR 表头算出来的那些列**，原样传进来 ——
  /// 有的课表只有 5 列，写死 7 等分会把一块课劈成两半）；
  /// [gutterRight] 是节次栏的右边界（第一节课列的左边界），
  /// 节次数字都在它左边；[yTop]/[yBottom] 是内容区的扫描范围
  /// （表头以下、导航栏以上，避免把蓝色学期条 / 底部导航当块）。
  ///
  /// 量不出节次行（比如整页没有课表网格）时返回 null，调用方退回纯文字路线。
  static TimetableGeometry? analyze({
    required int width,
    required int height,
    required Uint8List rgba,
    required List<GeometryBand> bands,
    required double gutterRight,
    required double yTop,
    required double yBottom,
  }) {
    if (rgba.length < width * height * 4) return null;

    // ---- 1. 节次栏标签：gutter 里的暗色低饱和文字，按 y 聚簇 ----
    final int xLabelEnd = gutterRight.round().clamp(1, width);
    final List<int> clusterRows = <int>[];
    int? clusterStart;
    for (int y = yTop.round(); y < yBottom.round() && y < height; y++) {
      bool dark = false;
      final int base = y * width * 4;
      for (int x = 0; x < xLabelEnd; x++) {
        final int p = base + x * 4;
        final int r = rgba[p], g = rgba[p + 1], b = rgba[p + 2];
        final int lum = (r * 299 + g * 587 + b * 114) ~/ 1000;
        final int mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
        final int mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
        if (lum < _labelLuminance && mx - mn < _labelSaturation) {
          dark = true;
          break;
        }
      }
      if (dark) {
        clusterStart ??= y;
      } else if (clusterStart != null) {
        clusterRows.add(clusterStart);
        clusterRows.add(y - 1);
        clusterStart = null;
      }
    }
    if (clusterStart != null) {
      clusterRows.add(clusterStart);
      clusterRows.add(yBottom.round() - 1);
    }

    final List<double> labels = <double>[];
    for (int i = 0; i + 1 < clusterRows.length; i += 2) {
      final double h = clusterRows[i + 1] - clusterRows[i] + 1;
      if (h < _labelMinHeight || h > _labelMaxHeight) continue;
      labels.add((clusterRows[i] + clusterRows[i + 1]) / 2);
    }
    // 节次栏至少要有 2 行才谈得上网格
    if (labels.length < 2) return null;

    // ---- 2. 课程块：逐列扫「强 / 弱行 + 迟滞」 ----
    //
    // ## 为什么是两档阈值（2026-10-07 真图实测，合成图测不出来）
    //
    // 课程块里的**白字行**会把彩色占比拉到 0.4~0.6 之间晃（字多的一行
    // 甚至掉到 0.16）：单一阈值 0.55 会把一块课切成好几段，短段再被
    // 最小高度丢掉。所以：
    //   - **强行**（占比 ≥ 0.5 且横向跨度 ≥ 75% 列宽）：只有块身够格 ——
    //     白字行占不满横向跨度，悬浮箭头（蓝色圆，只占列宽 ~40%）也不够，
    //     只有它有资格**开**一块
    //   - **弱行**（占比 ≥ 0.10）：块身里的文字行最低也有 0.16，够格续命；
    //     空白格线和块外都是 ~0
    //   - 块在**连续 2 行非弱行**后结束 —— 块与块之间是 2~3 行全白的
    //     网格线（够结束），而块内最糟也只是 1 行掉到 0（抗锯齿缝，
    //     1 行不断开）
    //   - 收尾后向上下各扩一段弱行（限 0.35 个行距），把块顶被文字
    //     拉低的头部捞回来
    final List<GeometryBlock> blocks = <GeometryBlock>[];
    final double pitch = _pitchOf(labels);
    final int yLo = (labels.first - pitch * 0.6).round().clamp(0, height - 1);
    final int yHi = (labels.last + pitch * 0.6).round().clamp(0, height);

    // 逐行的占比 / 跨度先算一遍（每列重复用同一行的采样结果）
    final int scanRows = yHi - yLo;
    final List<List<double>> bandFracs =
        List<List<double>>.generate(bands.length, (_) => List<double>.filled(scanRows, 0));
    final List<List<double>> bandSpans =
        List<List<double>>.generate(bands.length, (_) => List<double>.filled(scanRows, 0));
    // 每行的**块身底色**（只统计有色采样点，文字/白缝都不参与）——
    // 用来找块内底色变化点（= 相邻两门课的分界）
    final List<List<int>> bandR =
        List<List<int>>.generate(bands.length, (_) => List<int>.filled(scanRows, 0));
    final List<List<int>> bandG =
        List<List<int>>.generate(bands.length, (_) => List<int>.filled(scanRows, 0));
    final List<List<int>> bandB =
        List<List<int>>.generate(bands.length, (_) => List<int>.filled(scanRows, 0));
    final List<List<int>> bandN =
        List<List<int>>.generate(bands.length, (_) => List<int>.filled(scanRows, 0));
    for (int bi = 0; bi < bands.length; bi++) {
      final GeometryBand band = bands[bi];
      final double cx0 = band.left + 6;
      final double cx1 = band.right - 6;
      if (cx1 <= cx0) continue;
      final int sampleStep = ((cx1 - cx0) / 40).ceil().clamp(1, 20);
      final int sampleCount = ((cx1 - cx0) / sampleStep).ceil();
      // 复用缓冲：本行"有色且不暗"的采样点（打包成 lum<<24|r<<16|g<<8|b）
      final List<int> buf = <int>[];
      for (int y = yLo; y < yHi; y++) {
        buf.clear();
        int colored = 0;
        int minC = -1, maxC = -1;
        final int base = y * width * 4;
        for (int s = 0; s < sampleCount; s++) {
          final int x = (cx0 + s * sampleStep).round();
          if (x < 0 || x >= width) continue;
          final int p = base + x * 4;
          final int r = rgba[p], g = rgba[p + 1], b = rgba[p + 2];
          final int mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
          final int mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
          // 只看饱和度：白底/灰线的 RGB 差≈0，块底色（粉/浅蓝/朱红）的
          // 差都在 60+ —— 不要加亮度上限，否则接近纯色的浅色块会漏
          if (mx - mn > _blockSaturation) {
            colored++;
            if (minC < 0) minC = s;
            maxC = s;
          }
          if (mx - mn >= _blockSaturation && (r + g + b) >= 510) {
            buf.add((((r * 299 + g * 587 + b * 114) ~/ 1000) << 24) |
                (r << 16) |
                (g << 8) |
                b);
          }
        }
        bandFracs[bi][y - yLo] = colored / sampleCount;
        bandSpans[bi][y - yLo] =
            minC < 0 ? 0 : (maxC - minC + 1) / sampleCount;
        // 底色 = 本行**最亮的那批**有色像素的平均。
        // ⚠️ 不能用全部有色像素的平均：文字的抗锯齿边缘也"有色"
        // （`#7f7170` 饱和度 15），只占 2% 就能把均值拉暗 7 以上 ——
        // 和真实的两块底色差（12~13）同量级，会造出一堆假边界。
        // 底色是块里最亮的颜色，取"离最亮 6 以内"的那批就干净了。
        int sr = 0, sg = 0, sb = 0, sn = 0;
        if (buf.isNotEmpty) {
          int maxLum = 0;
          for (final int v in buf) {
            final int l = v >>> 24;
            if (l > maxLum) maxLum = l;
          }
          for (final int v in buf) {
            if ((v >>> 24) < maxLum - 6) continue;
            sr += (v >> 16) & 0xFF;
            sg += (v >> 8) & 0xFF;
            sb += v & 0xFF;
            sn++;
          }
        }
        bandR[bi][y - yLo] = sr;
        bandG[bi][y - yLo] = sg;
        bandB[bi][y - yLo] = sb;
        bandN[bi][y - yLo] = sn;
      }
    }

    for (int bi = 0; bi < bands.length; bi++) {
      final GeometryBand band = bands[bi];
      final double cx0 = band.left + 6;
      final double cx1 = band.right - 6;
      if (cx1 <= cx0) continue;
      final List<double> fracs = bandFracs[bi];
      final List<double> spans = bandSpans[bi];

      int? runStart;
      int lastGood = -1; // 最近一个弱行及以上的行号
      int missRun = 0;
      void closeBlob() {
        if (runStart == null) return;
        final int top = runStart!;
        final int bottom = lastGood;
        runStart = null;
        lastGood = -1;
        if (bottom - top + 1 < _minBlockHeight.round()) return;
        // 前后各扩一段弱行：块顶/块底被白字拉低的边缘捞回来
        final int maxExtend = (pitch * 0.35).round();
        int extTop = top;
        while (extTop > yLo &&
            top - extTop < maxExtend &&
            fracs[extTop - 1 - yLo] >= 0.10) {
          extTop--;
        }
        int extBottom = bottom;
        while (extBottom + 1 < yHi &&
            extBottom - bottom < maxExtend &&
            fracs[extBottom + 1 - yLo] >= 0.10) {
          extBottom++;
        }
        // ## 中位跨度是块的"身份证"（2026-10-07 真图实测补的）
        //
        // 块身每一行都横跨整列（文字行也是 —— 字缝里露的是块底色），
        // 中位跨度 0.96~1.00；悬浮箭头是**圆**，只有中间几行够宽，
        // 完整圆的中位跨度 ~0.68。⚠️ 中位数必须在**扩展后的整段**上算：
        // 圆的上半部够不上"强行"、不在运行段里，只算运行段会把中位数
        // 抬回 0.77 混过去（这一刀改了两次才切准）。
        final List<double> blobSpans = <double>[
          for (int y = extTop; y <= extBottom; y++) spans[y - yLo],
        ]..sort();
        final double medianSpan = blobSpans.isEmpty
            ? 0
            : blobSpans[blobSpans.length ~/ 2];
        if (medianSpan < _strongSpan) return;
        blocks.add(GeometryBlock(
          left: band.left,
          top: extTop.toDouble(),
          right: band.right,
          bottom: extBottom.toDouble(),
          colorEdges: _colorEdgesIn(
            bandR[bi], bandG[bi], bandB[bi], bandN[bi], fracs, yLo, extTop,
            extBottom,
          ),
        ));
      }

      for (int y = yLo; y < yHi; y++) {
        final bool strong =
            fracs[y - yLo] >= _strongFrac && spans[y - yLo] >= _strongSpan;
        final bool weak = fracs[y - yLo] >= _weakFrac;
        if (runStart == null) {
          if (strong) {
            runStart = y;
            lastGood = y;
            missRun = 0;
          }
        } else {
          if (weak) {
            lastGood = y;
            missRun = 0;
          } else {
            missRun++;
            if (missRun >= 2) {
              closeBlob(); // 用 lastGood 当底边
            }
          }
        }
      }
      closeBlob();
    }

    return TimetableGeometry(labelCentersY: labels, blocks: blocks);
  }

  static double _pitchOf(List<double> labels) {
    if (labels.length < 2) return 100;
    final List<double> gaps = <double>[
      for (int i = 1; i < labels.length; i++) labels[i] - labels[i - 1],
    ]..sort();
    return gaps[gaps.length ~/ 2];
  }

  /// 块内**底色变化点**的 y（升序）。见 [GeometryBlock.colorEdges]。
  ///
  /// 比较的是「前后各 ~16px 处的底色平均」而不是单行 —— 单行会被抗锯齿
  /// 噪声骗。
  ///
  /// ⚠️ 底色只统计**纯块身行**（彩色占比 ≥ 0.9，即这一行没有文字）：
  /// 文字行的抗锯齿边缘会把底色拉暗，实测能拉出 14 的假色差 ——
  /// 和真实的两块底色差（12~13）一样大，不加这道闸全是假边界。
  ///
  /// 阈值 7：实测相邻两门课的底色最大通道差是 12~13（粉 vs 米黄 13、
  /// 米黄 vs 浅黄 12、黄 vs 粉 13），纯块身行的波动 ≤ 2。
  static List<ColorEdge> _colorEdgesIn(
    List<int> rowR,
    List<int> rowG,
    List<int> rowB,
    List<int> rowN,
    List<double> fracs,
    int yLo,
    int extTop,
    int extBottom,
  ) {
    (int, int, int)? colorNear(int y) {
      int sr = 0, sg = 0, sb = 0, n = 0;
      for (int yy = y - 12; yy <= y + 12; yy++) {
        final int i = yy - yLo;
        if (i < 0 || i >= rowN.length || rowN[i] == 0) continue;
        if (fracs[i] < 0.9) continue; // 有文字的行不参与
        // rowR/G/B 存的是该行所有有色采样点的**和**，先折回均值再跨行平均
        sr += rowR[i] ~/ rowN[i];
        sg += rowG[i] ~/ rowN[i];
        sb += rowB[i] ~/ rowN[i];
        n++;
      }
      if (n < 3) return null;
      return (sr ~/ n, sg ~/ n, sb ~/ n);
    }

    int diff((int, int, int) a, (int, int, int) b) {
      final int dr = (a.$1 - b.$1).abs();
      final int dg = (a.$2 - b.$2).abs();
      final int db = (a.$3 - b.$3).abs();
      return dr > dg ? (dr > db ? dr : db) : (dg > db ? dg : db);
    }

    final List<ColorEdge> edges = <ColorEdge>[];
    int runStart = -1;
    int bestY = -1;
    int bestDiff = 0;
    void flushRun() {
      if (runStart < 0 || bestY < 0) return;
      edges.add(ColorEdge(bestY.toDouble(), bestDiff));
      runStart = -1;
      bestY = -1;
      bestDiff = 0;
    }

    for (int y = extTop + 16; y <= extBottom - 16; y += 2) {
      final (int, int, int)? a = colorNear(y - 16);
      final (int, int, int)? b = colorNear(y + 16);
      final int d = (a == null || b == null) ? 0 : diff(a, b);
      if (d > 7) {
        if (runStart < 0) runStart = y;
        if (d > bestDiff) {
          bestDiff = d;
          bestY = y;
        }
      } else {
        flushRun();
      }
    }
    flushRun();
    return edges;
  }
}
