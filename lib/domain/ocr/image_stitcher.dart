import 'package:meta/meta.dart';

/// 一张图的「行特征」—— 每行一个定长的亮度向量。
///
/// ## 为什么要降采样
///
/// 对缝要在几百个候选偏移里逐一比对，直接拿 1080×2400 的原图逐像素算是算不动的。
/// 而且降采样还顺带**滤掉噪声**（截图压缩产生的细碎色差），留下的正是
/// "这一行长什么样"的粗结构 —— 对齐需要的就是这个信号。
///
/// 数据按行优先存：`values[row * columns + col]`，取值 0~255 的亮度。
@immutable
class RowSignature {
  const RowSignature({
    required this.rowCount,
    required this.columns,
    required this.values,
  });

  final int rowCount;
  final int columns;

  /// 长度必须等于 `rowCount * columns`
  final List<int> values;

  /// 从"按行优先、每行 columns 个亮度值"的原始数组建特征。
  /// 服务层负责把 `ui.Image` 降采样并转成亮度数组。
  static RowSignature fromLuminance({
    required int rowCount,
    required int columns,
    required List<int> luminance,
  }) {
    assert(rowCount > 0 && columns > 0, '行列数必须为正');
    assert(
      luminance.length == rowCount * columns,
      '亮度数组长度应为 $rowCount × $columns = ${rowCount * columns}，'
      '实际 ${luminance.length}',
    );
    return RowSignature(
      rowCount: rowCount,
      columns: columns,
      values: luminance,
    );
  }

  /// 从顶部裁掉 [rows] 行
  RowSignature cropTop(int rows) {
    if (rows <= 0) return this;
    final int r = rows >= rowCount ? rowCount : rows;
    return RowSignature(
      rowCount: rowCount - r,
      columns: columns,
      values: values.sublist(r * columns),
    );
  }
}

/// 对缝结果
@immutable
class StitchMatch {
  const StitchMatch({
    required this.overlapRows,
    required this.matchedRows,
    required this.meanDiff,
    required this.confidence,
  });

  /// 重叠区总高：上半的最后 [overlapRows] 行 对 下半的最前 [overlapRows] 行。
  /// **拼接时要按这个值把下半张往上挪。**
  final int overlapRows;

  /// 重叠区里**真正连续对上**的那一段有多长。
  ///
  /// [overlapRows] 减掉它就是"下半张顶部那段对不上的内容"——
  /// 通常是手机状态栏 + 应用自己的标题栏（见下面 [findVerticalOverlap] 的说明）。
  final int matchedRows;

  /// 对上的那一段的平均绝对亮度差（0~255，越小越像）
  final double meanDiff;

  /// 0~1 的置信度。太低就别自动拼，交给用户手动对。
  final double confidence;

  /// 下半张顶部有多少行是"对不上、要丢掉"的
  int get skippedTopRows => overlapRows - matchedRows;

  @override
  String toString() => 'StitchMatch(重叠 $overlapRows 行，'
      '其中对上 $matchedRows 行，顶部跳过 $skippedTopRows 行，'
      '平均差 ${meanDiff.toStringAsFixed(2)}，'
      '置信度 ${(confidence * 100).round()}%)';
}

/// 一张图上下两端各有多少行是**固定装饰**（手机状态栏 / 应用标题栏 /
/// 悬浮按钮 / 底部导航栏）。
///
/// 这些行在两张截图里位置**完全一样**、不属于滚动内容。对缝时必须把它们
/// 排除在比对范围之外，理由见 [detectChrome]。
@immutable
class ChromeInsets {
  const ChromeInsets({this.top = 0, this.bottom = 0});

  static const ChromeInsets none = ChromeInsets();

  final int top;
  final int bottom;

  bool get isEmpty => top <= 0 && bottom <= 0;

  @override
  String toString() => 'ChromeInsets(上 $top 行 / 下 $bottom 行)';
}

/// 认出两张截图上下两端那一段**位置固定、不属于滚动内容**的行。
///
/// ## 为什么这一步是必须的（2026-10-06 真机实测栽的第二次）
///
/// 真实课表截图长这样（数字是实测的真实行号，图高 2608）：
///
/// ```
///    0 ~  777  状态栏 + 红色标题栏 + 蓝色学期条 + 「周一~周日」表头   ← 固定
///  778 ~ 2375  节次内容（真正会滚动的部分）
/// 2376 ~ 2607  底部导航栏 + 左右箭头 + 悬浮「+」按钮                ← 固定
/// ```
///
/// 固定装饰**同时出现在重叠区的开头和结尾**。这带来两个后果：
///   1. 从末尾往回扫找"连续对上"的段，**第一行就撞上底部导航栏**，
///      直接判定"没有连续段" —— 明明中间有 919 行是精确对上的
///   2. 那 778 行的顶部装饰在"最长连续段"排名里能排到第二，
///      会跟真正的答案抢（实测：装饰 778 行 vs 真答案 919 行，只差一点）
///
/// 所以先认出来、排除掉，剩下的比对就干净了。
///
/// ## 怎么认
///
/// 装饰在同一位置上两张图**长得一模一样**，所以就是"零位移下的公共前缀 /
/// 公共后缀"。允许最多 [maxMiss] 行连续不一致 —— 状态栏里的时钟隔几分钟
/// 就会跳字，不能因为一行不同就打断。
///
/// 兜底：两张图本来就几乎一样（公共部分超过 [maxRatio]）时，说明压根没滚动，
/// 这时候"装饰"无从谈起，返回 [ChromeInsets.none]。
ChromeInsets detectChrome(
  RowSignature top,
  RowSignature bottom, {
  double rowThreshold = 8,
  int maxMiss = 3,
  double maxRatio = 0.4,
}) {
  assert(top.columns == bottom.columns, '两张图必须降到同一列数才能比');

  final int limit = top.rowCount < bottom.rowCount
      ? top.rowCount
      : bottom.rowCount;

  final int prefix = _commonRun(
    limit,
    (int i) => _rowMeanDiff(top, bottom, i, i),
    rowThreshold,
    maxMiss,
  );
  final int suffix = _commonRun(
    limit,
    (int i) => _rowMeanDiff(
      top,
      bottom,
      top.rowCount - 1 - i,
      bottom.rowCount - 1 - i,
    ),
    rowThreshold,
    maxMiss,
  );

  final int cap = (limit * maxRatio).round();
  final int p = prefix > cap ? cap : prefix;
  final int s = suffix > cap ? cap : suffix;

  // 上下装饰加起来盖住了大半张图 → 这两张图本来就几乎一样，别乱裁
  if (p + s > limit * 0.5) return ChromeInsets.none;

  return ChromeInsets(top: p, bottom: s);
}

/// 从 [from] 那一端起，最多能连续"像"多少行（允许 [maxMiss] 行连续不一致）
int _commonRun(
  int limit,
  double Function(int) diffAt,
  double threshold,
  int maxMiss,
) {
  int lastGood = 0;
  int miss = 0;
  for (int i = 0; i < limit; i++) {
    if (diffAt(i) <= threshold) {
      miss = 0;
      lastGood = i + 1;
    } else {
      miss++;
      if (miss > maxMiss) break;
    }
  }
  return lastGood;
}

/// 找两张"上下两半"截图的垂直重叠高度。**纯函数，宿主机可直接单测。**
///
/// ## 思路
///
/// 同一张长图截成上下两半后，**上半的尾巴**和**下半的开头**会有一段是同一内容。
/// 于是把重叠高度 o 从 [minOverlapRows] 一路试到两图中较矮的那个，
/// 比对「上半最后 o 行」和「下半最前 o 行」。
///
/// ## ⚠️ 三个必须处理的现实
///
/// 1. **固定装饰要排除**。真实截图上下两端都有状态栏 / 标题栏 / 导航栏这类
///    位置不变的东西（见 [detectChrome]）。它们既会挡住"从末尾往回扫"，
///    又会在排名里跟真答案抢。所以比对范围先按 [chrome] 收窄
/// 2. **找的是"最长的一段连续对上"，不是"整段平均像不像"**。装饰和滚动内容
///    混在重叠区里，整段平均会被拉高，判成"没有重叠"。要的是最长的那一段
///    连续对上 —— 它才是真正共享的内容
/// 3. **对上就得是逐像素精确对上**。服务层把纵向保持原始分辨率，位移是整数，
///    同一段内容两张图本来就一模一样，差异≈0
///
/// 找不到够像的重叠时返回 **null** —— 宁可不拼，也不要拼错。
StitchMatch? findVerticalOverlap({
  required RowSignature top,
  required RowSignature bottom,
  ChromeInsets chrome = ChromeInsets.none,
  int minOverlapRows = 6,
  double maxMeanDiff = 15,
  double goodRowDiff = 12,
  double minRunRatio = 0.5,
}) {
  assert(top.columns == bottom.columns, '两张图必须降到同一列数才能比');

  final int maxOverlap = top.rowCount < bottom.rowCount
      ? top.rowCount
      : bottom.rowCount;
  if (maxOverlap < minOverlapRows) return null;

  int bestRun = 0;
  double bestRunMean = double.infinity;
  int bestOverlap = 0;

  for (int o = minOverlapRows; o <= maxOverlap; o++) {
    // 这一步里两张图各自的可用行范围（去掉固定装饰）
    final int aShift = top.rowCount - o;
    final int rLo = _max2(chrome.top, chrome.top - aShift);
    final int rHi = _min2(bottom.rowCount - chrome.bottom, o - chrome.bottom);
    if (rHi - rLo < minOverlapRows) continue;

    // 找最长的一段连续对上
    int run = 0;
    double curSum = 0;
    int localBest = 0;
    double localBestSum = 0;
    for (int r = rLo; r < rHi; r++) {
      final double d = _rowMeanDiff(top, bottom, aShift + r, r);
      if (d <= goodRowDiff) {
        run++;
        curSum += d;
        if (run > localBest) {
          localBest = run;
          localBestSum = curSum;
        }
      } else {
        run = 0;
        curSum = 0;
      }
      // 剪枝：剩下多少行都不够追上当前全局最好成绩了，提前收工
      if (localBest + (rHi - 1 - r) <= bestRun) break;
    }

    if (localBest == 0) continue;
    final double mean = localBestSum / localBest;
    if (localBest > bestRun ||
        (localBest == bestRun && mean < bestRunMean)) {
      bestRun = localBest;
      bestRunMean = mean;
      bestOverlap = o;
    }
  }

  if (bestRun < minOverlapRows) return null;
  if (bestRunMean > maxMeanDiff) return null;

  // 对上的部分必须占"可用重叠区"的大部分 —— 否则就是在一大堆对不上的行里
  // 捡到一小撮碰巧一样的（课表大片留白处很容易出现这种）
  final int usable = _min2(
        bottom.rowCount - chrome.bottom,
        bestOverlap - chrome.bottom,
      ) -
      _max2(chrome.top, chrome.top - (top.rowCount - bestOverlap));
  if (usable > 0 && bestRun < usable * minRunRatio) return null;

  return StitchMatch(
    overlapRows: bestOverlap,
    matchedRows: bestRun,
    meanDiff: bestRunMean,
    confidence: (1 - bestRunMean / maxMeanDiff).clamp(0.0, 1.0),
  );
}

int _max2(int a, int b) => a > b ? a : b;
int _min2(int a, int b) => a < b ? a : b;

/// 第 [i] 行（上半）与第 [j] 行（下半）的平均绝对亮度差
double _rowMeanDiff(RowSignature top, RowSignature bottom, int i, int j) {
  final int aBase = i * top.columns;
  final int bBase = j * bottom.columns;
  int sum = 0;
  for (int c = 0; c < top.columns; c++) {
    sum += (top.values[aBase + c] - bottom.values[bBase + c]).abs();
  }
  return sum / top.columns;
}
