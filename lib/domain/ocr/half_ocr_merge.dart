import 'package:meta/meta.dart';

import 'ocr_result.dart';

/// 把「上半张」「下半张」**各自 OCR** 的结果，合并到**拼图坐标系**里。
///
/// ## 为什么不能直接 OCR 拼好的那张高图（2026-10-07 真机实测）
///
/// 同一份内容，两张 887×1920 的截图：
///
/// | 节次号 | 分别 OCR 原图 | 拼成 887×2494 后再 OCR |
/// |---|---|---|
/// | 第 1 节 | `1` ✅ | **整块漏读** ❌ |
/// | 第 2 节 | `2` ✅ | `2。%` ❌ |
/// | 第 3 节 | `3` ✅ | `3閃8` ❌ |
/// | 第 6 节 | `6` ✅ | **整块漏读** ❌ |
/// | 第 8 节 | `8` ✅ | `8m以` ❌ |
///
/// 根因：ML Kit 会把整图按长边缩放进模型输入尺寸 —— **图越高、缩放比越小**，
/// 节次号这种小字号就糊没了（还会跟旁边的时刻粘成一块）。
///
/// 所以：**分别 OCR 两张原图（各自保持原始分辨率），再按拼接几何合并**。
/// 既保住"一张连续网格"的版面信息，又不牺牲识别质量。
///
/// ## 坐标变换
///
/// 拼图 = 上半张的 `[0, dstY)` + 下半张的 `[srcTop, bottomHeight)`。于是：
///   - 上半张的 y **原样保留**（落在自己底部装饰里的丢掉）
///   - 下半张的 y 整体平移 `dstY - srcTop`（顶部那段没接上来的丢掉）
///
/// 两段在拼图里**互不重叠**，所以合并结果不需要去重。
@immutable
class HalfOcrMerge {
  const HalfOcrMerge({required this.blocks, required this.droppedTop});

  /// 合并后、位于拼图坐标系里的文本行（按 y 升序）
  final List<OcrBlock> blocks;

  /// 上半张里被丢掉的文本行数（落在它自己的底部装饰里）
  final int droppedTop;

  int get length => blocks.length;
}

List<OcrBlock> mergeHalfOcrBlocks({
  required List<OcrBlock> topBlocks,
  required List<OcrBlock> bottomBlocks,
  required int dstY,
  required int srcTop,
}) =>
    mergeHalfOcr(
      topBlocks: topBlocks,
      bottomBlocks: bottomBlocks,
      dstY: dstY,
      srcTop: srcTop,
    ).blocks;

/// 同 [mergeHalfOcrBlocks]，但额外报告丢了多少行（诊断用）
HalfOcrMerge mergeHalfOcr({
  required List<OcrBlock> topBlocks,
  required List<OcrBlock> bottomBlocks,
  required int dstY,
  required int srcTop,
}) {
  final double delta = (dstY - srcTop).toDouble();
  final List<OcrBlock> out = <OcrBlock>[];
  int dropped = 0;

  // ## 交叠区按**中心线**判归属（2026-10-07 真机实测踩到）
  //
  // 两张图在交叠区里会**各自识别出同一行文字**（实测 `@教2-` 下面那个 `311`
  // 上半张给了一份、下半张又给了一份，拼出来是 `@教2-311311`）。
  // 所以必须以拼缝为界**二选一**，不能两边的都收：
  //   - 中心线在拼缝**上方** → 归上半张
  //   - 中心线在拼缝**下方** → 归下半张
  // 跨缝的行只会归给其中一边，另一边那份被丢掉。
  for (final OcrBlock b in topBlocks) {
    if ((b.top + b.bottom) / 2 >= dstY) {
      dropped++; // 落在上半张自己的底部装饰里，或跨缝后归了下半张
      continue;
    }
    out.add(OcrBlock(
      text: b.text,
      left: b.left,
      top: b.top,
      right: b.right,
      // 跨过拼接线的行：裁到线为止，别让它盖住下半张的内容
      bottom: b.bottom > dstY ? dstY.toDouble() : b.bottom,
      // 词级坐标：上半张的 y 原样（只把越界的那部分裁到拼缝）
      words: <OcrWord>[
        for (final OcrWord w in b.words)
          OcrWord(
            text: w.text,
            left: w.left,
            top: w.top,
            right: w.right,
            bottom: w.bottom > dstY ? dstY.toDouble() : w.bottom,
          ),
      ],
    ));
  }

  for (final OcrBlock b in bottomBlocks) {
    final double t = b.top + delta;
    final double bt = b.bottom + delta;
    if ((t + bt) / 2 < dstY) continue; // 跨缝的上半段归上半张
    if (bt <= 0) continue;
    final double top = t < dstY ? dstY.toDouble() : t;
    out.add(OcrBlock(
      text: b.text,
      left: b.left,
      top: top,
      right: b.right,
      bottom: bt,
      // 词级坐标：下半张整体平移 delta（和行坐标同一个变换）
      words: <OcrWord>[
        for (final OcrWord w in b.words)
          OcrWord(
            text: w.text,
            left: w.left,
            top: w.top + delta,
            right: w.right,
            bottom: w.bottom + delta,
          ),
      ],
    ));
  }

  out.sort((OcrBlock a, OcrBlock b) {
    final int byTop = a.top.compareTo(b.top);
    return byTop != 0 ? byTop : a.left.compareTo(b.left);
  });
  return HalfOcrMerge(blocks: out, droppedTop: dropped);
}
