import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/ocr/image_stitcher.dart';

/// 拼图结果
@immutable
class StitchOutcome {
  const StitchOutcome({
    required this.path,
    required this.overlapPixels,
    required this.width,
    required this.height,
    this.chrome = ChromeInsets.none,
    this.swapped = false,
    this.match,
    this.dstY = 0,
    this.srcTop = 0,
    this.effectiveTopPath = '',
    this.effectiveBottomPath = '',
  });

  /// 拼好的整张图（PNG，落在应用缓存目录里，可以直接喂给识别器）
  final String path;

  /// ⚠️ **分半 OCR 时必须用这两条路径，而不是用户选的那两条。**
  ///
  /// 用户把上下两张选反了时，[stitchAuto] 会**内部交换**再拼 ——
  /// 拼图是对的，`dstY`/`srcTop` 也是按交换后的几何算的。
  /// 但调用方如果还拿"用户选的原始路径"去分别 OCR，就会出现
  /// **几何按 A 算、图片是 B 的顺序**：坐标映射全乱，
  /// 表现是"拼图看着没问题，识别结果却一塌糊涂"
  /// （2026-10-09 用户报的 bug）。
  ///
  /// 所以这里把**实际用于拼接的那两条路径**原样带出来，调用方直接用。
  /// 没交换时它们就等于用户选的那两条。
  final String effectiveTopPath;
  final String effectiveBottomPath;

  /// 重叠了多少**原图像素**
  final int overlapPixels;

  /// 两张截图上下两端那一段**位置固定、不跟着滚动**的装饰
  /// （状态栏 / 标题栏 / 悬浮按钮 / 底部导航栏）。
  ///
  /// 拼接要按它算出"内容区"在哪 —— 上半张自己的底部导航栏要丢掉，
  /// 下半张的接续位置也要按内容区算（见 [_compose]）。
  final ChromeInsets chrome;

  /// 用户把上下两张选反了，算法自动换过来处理的。
  /// 界面上该提一句，免得用户以为"我选对了呀"。
  final bool swapped;

  final int width;
  final int height;

  /// 上半张的**内容区末尾**落在拼图的第几行（= `topHeight - chrome.bottom`）。
  ///
  /// 拼图 = 上半张的 `[0, dstY)` + 下半张的 `[srcTop, bottomHeight)`。
  /// 识别时要把两张图**各自 OCR** 的结果按这两个值合并到拼图坐标系
  /// （为什么不能直接 OCR 拼好的高图，见 `half_ocr_merge.dart`）。
  final int dstY;

  /// 下半张从**它自己的第几行**开始接上来
  final int srcTop;

  /// 自动对缝时的匹配信息；用户手动指定重叠高度时为 null
  final StitchMatch? match;

  /// 置信度够不够高。不够时 UI 要提醒用户"自己看一眼、必要时手动对一下"
  ///
  /// 0.5 对应得分 7.5（阈值是 15）：真重叠的得分在 1~2，也就是 0.87 以上；
  /// 卡在 0.5 意味着"只有明显不像的重叠才会被判为不放心"。
  bool get isConfident => (match?.confidence ?? 1.0) >= 0.5;
}

/// 把"上下两半"两张课表截图拼成一张完整的。
///
/// ## 流程
///
/// 1. **降采样看结构**：两张图各解一份 64 像素宽的小图，转成"每行的亮度向量"。
///    这一步只为了找重叠，不为了画图 —— 小图内存开销可以忽略
/// 2. **找重叠**：交给纯函数 [findVerticalOverlap]（算法与踩坑见它的注释）
/// 3. **按原图拼接**：小图上的重叠行数换算回原图像素，再用 `PictureRecorder`
///    把两张原图叠起来（第二张上移「重叠高度」那么多）
/// 4. **落文件**：编码成 PNG 写进缓存目录 —— 识别器吃的是文件路径
///
/// ## 为什么分两次解码
///
/// 找重叠只需要 64 像素宽的小图，拼接才需要原图。分两步能把峰值内存压下来：
/// 1080×2400 的 ARGB 位图一张就是 ~10MB，两张一起再叠一份输出很容易把
/// 低内存机器顶掉。先解小的，用完立刻 dispose，再解原图。
class ImageStitchService {
  const ImageStitchService({this.outputDirOverride});

  /// 测试用：把输出目录固定下来（正式运行时传 null，走应用缓存目录）
  final Directory? outputDirOverride;

  /// 找重叠用的**横向**降采样宽度（纵向保持原始分辨率）。
  ///
  /// ## 为什么纵向必须 1:1（2026-10-06 实测逼出来的）
  ///
  /// 一开始横向纵向一起缩（把 2400 像素高的图压成 360 行）。问题来了：
  /// 两张图的真实位移是一个**整数像素**值，但它除以缩放比之后就不再是整数，
  /// 真正的对齐落在两行之间。于是重叠区里凡是有横向边缘的那些行（也就是
  /// **每一行文字**）都会差半行、差异被放大，连续对上的段落被反复打断 ——
  /// 实测只能对上 13 行，判成"拼不上"。
  ///
  /// 纵向保持 1:1 之后：一行特征 = 一个原始像素行，位移就是整数，
  /// 对上就是**逐像素精确对上**（两张截图的同一段内容本来就一模一样），
  /// 差异接近 0，连续段能一直连下去。
  ///
  /// 代价：行数从几百涨到几千。但"从末尾往回扫、遇到第一处不像就停"这个
  /// 写法让绝大多数候选位移在第一行就被否掉，实际运算量反而比以前小。
  ///
  /// 横向 96 列够用：对缝比的是"这一行长什么样"的粗结构，
  /// 再细也提不出更多信息，只是白花内存。
  static const int _sampleColumns = 96;

  /// 重叠区至少要占画面这么高才认（见 `stitchAuto` 里的说明）
  static const double _minOverlapRatio = 0.06;

  /// 自动找重叠并拼接。找不到够像的重叠时返回 **null**（宁可不拼也不拼错）。
  Future<StitchOutcome?> stitchAuto({
    required String topPath,
    required String bottomPath,
  }) async {
    // ## 先比**原始**宽度
    //
    // 缩到同一列数后，"一行"代表的实际高度才是同一个尺度，算出来的重叠行数
    // 才能换算回原图像素。宽度不同就说明这两张图不是同一台设备、同一版面的
    // 截图，硬拼没有意义。
    //
    // ⚠️ 2026-10-06 踩过：一开始拿**降采样后**的列数比 —— 两边都强制缩到
    // `_sampleWidth`，列数永远相等，这个检查等于没写。必须比原始宽度。
    final ({int width, int height}) topSize = await _sizeOf(topPath);
    final ({int width, int height}) bottomSize = await _sizeOf(bottomPath);
    if (topSize.width != bottomSize.width) {
      if (kDebugMode) {
        debugPrint('[STITCH] 两张图宽度不同'
            '（${topSize.width} vs ${bottomSize.width}），放弃自动对缝');
      }
      return null;
    }

    // 纵向 1:1（见 _sampleColumns 的说明）：一行特征 = 一个原始像素行，
    // 所以算出来的重叠行数**就是像素数**，不需要再换算一次
    final RowSignature topSig = await _signatureOf(
      topPath,
      width: _sampleColumns,
      height: topSize.height,
    );
    final RowSignature bottomSig = await _signatureOf(
      bottomPath,
      width: _sampleColumns,
      height: bottomSize.height,
    );

    // 重叠区至少要占画面这么高才认。
    // 为什么不能太小：课表有大片留白，"两行都几乎是白的"时差异天然很低，
    // 一小撮碰巧一样的行很容易凑出一个假的"对上了"。
    final int minSample = topSig.rowCount < bottomSig.rowCount
        ? topSig.rowCount
        : bottomSig.rowCount;
    final int minOverlapRows =
        (minSample * _minOverlapRatio).round().clamp(12, 2000);

    // 先认出上下两端那一段"位置固定、不跟着滚动"的装饰
    // （状态栏 / 标题栏 / 表头 / 悬浮按钮 / 底部导航栏）——
    // 不排除掉的话，它既会挡住"找连续段"，又会在排名里跟真答案抢
    final ChromeInsets chrome = detectChrome(topSig, bottomSig);

    // 正着找一次；找不到就把上下两张**换个位置再找一次**。
    //
    // 为什么需要这一步：算法假设"第二张在第一张下面"。用户把上下两张选进
    // 对方的格子里是很常见的手滑，而一旦反了，**任何位移都对不上**。
    final StitchMatch? forward = findVerticalOverlap(
      top: topSig,
      bottom: bottomSig,
      chrome: chrome,
      minOverlapRows: minOverlapRows,
    );
    final StitchMatch? reversed = forward != null
        ? null
        : findVerticalOverlap(
            top: bottomSig,
            bottom: topSig,
            chrome: chrome,
            minOverlapRows: minOverlapRows,
          );

    final bool swapped = forward == null && reversed != null;
    final StitchMatch? match = forward ?? reversed;

    if (kDebugMode) {
      debugPrint('[STITCH] 特征 ${topSig.rowCount}×${topSig.columns} / '
          '${bottomSig.rowCount}×${bottomSig.columns}，'
          '最少重叠 $minOverlapRows 行，固定装饰 $chrome');
      debugPrint('[STITCH] 正着 → $forward');
      debugPrint('[STITCH] 反着 → $reversed');
    }
    if (match == null) return null;

    return _compose(
      topPath: swapped ? bottomPath : topPath,
      bottomPath: swapped ? topPath : bottomPath,
      overlapPixels: match.overlapRows,
      chrome: chrome,
      swapped: swapped,
      match: match,
    );
  }

  /// 用**指定的**重叠高度拼接 —— 用户在确认页手动微调时走这条路。
  ///
  /// [chrome] 要原样带上自动对缝时认出来的固定装饰，
  /// 否则手动微调会把状态栏 / 导航栏当成内容拼进去。
  Future<StitchOutcome> stitchWithOverlap({
    required String topPath,
    required String bottomPath,
    required int overlapPixels,
    ChromeInsets chrome = ChromeInsets.none,
  }) =>
      _compose(
        topPath: topPath,
        bottomPath: bottomPath,
        overlapPixels: overlapPixels,
        chrome: chrome,
      );

  // ------------------------------------------------------------------

  Future<StitchOutcome> _compose({
    required String topPath,
    required String bottomPath,
    required int overlapPixels,
    ChromeInsets chrome = ChromeInsets.none,
    bool swapped = false,
    StitchMatch? match,
  }) async {
    final ui.Image top = await _decodeFull(topPath);
    final ui.Image bottom = await _decodeFull(bottomPath);

    try {
      // 滚动量：上半张的第 i 行 = 下半张的第 i − shift 行
      // 重叠不可能超过较矮那张的高度
      final int maxOverlap =
          top.height < bottom.height ? top.height : bottom.height;
      final int overlap = overlapPixels.clamp(0, maxOverlap);
      final int shift = top.height - overlap;

      // ## 拼接要按「内容区」算，不能按「整张图」算（2026-10-06 真机实测）
      //
      // 真实截图上下两端都有固定装饰（状态栏 / 标题栏 / 底部导航栏）。所以：
      //   - 上半张**自己的底部导航栏要丢掉** —— 它不是内容，留着会横在拼接处
      //   - 下半张要接上来的，是「它内容区里、对应上半张内容区末尾之后」的那一段
      //
      // 一开始按整张图算（下半张从 overlap 行之后全接上），结果上半张的导航栏
      // 留在了中间，把下半张该接的那 546 行内容整个挤掉 —— 下半段课表就没了。
      final int contentHeight = top.height - chrome.top - chrome.bottom;
      final int dstY = top.height - chrome.bottom;

      int srcTop = chrome.top + contentHeight - shift;
      srcTop = srcTop.clamp(0, bottom.height);
      final double srcHeight = (bottom.height - srcTop).toDouble();

      final int width = top.width;
      final int height = dstY + srcHeight.round();

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(recorder);
      final ui.Paint paint = ui.Paint()
        ..filterQuality = ui.FilterQuality.medium;

      // 上半张：只画到"内容区末尾"为止（它的底部导航栏不要）
      canvas.drawImageRect(
        top,
        ui.Rect.fromLTWH(0, 0, top.width.toDouble(), dstY.toDouble()),
        ui.Rect.fromLTWH(0, 0, top.width.toDouble(), dstY.toDouble()),
        paint,
      );

      // 下半张：从它内容区里对应的位置开始，接在上半张内容区末尾后面
      // （它自带的那条底部导航栏正好落在整张图的最下面，位置天然是对的）
      if (srcHeight > 0) {
        canvas.drawImageRect(
          bottom,
          ui.Rect.fromLTWH(
            0,
            srcTop.toDouble(),
            bottom.width.toDouble(),
            srcHeight,
          ),
          ui.Rect.fromLTWH(
            0,
            dstY.toDouble(),
            bottom.width.toDouble(),
            srcHeight,
          ),
          paint,
        );
      }

      final ui.Picture picture = recorder.endRecording();
      final ui.Image merged = await picture.toImage(width, height);
      picture.dispose();

      final ByteData? png =
          await merged.toByteData(format: ui.ImageByteFormat.png);
      merged.dispose();
      if (png == null) {
        throw StateError('拼好的图编码 PNG 失败');
      }

      final Directory dir = await _outputDir();
      final String path =
          '${dir.path}/stitched_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(path).writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        flush: true,
      );

      if (kDebugMode) {
        debugPrint('[STITCH] 输出 $width×$height'
            '（滚动 $shift 像素，固定装饰 $chrome，'
            '下半张从第 $srcTop 行接上）→ $path');
      }

      return StitchOutcome(
        path: path,
        overlapPixels: overlap,
        chrome: chrome,
        swapped: swapped,
        width: width,
        height: height,
        dstY: dstY,
        srcTop: srcTop,
        match: match,
        // 传进来的 topPath / bottomPath 已经是**交换后**的（见 stitchAuto），
        // 原样带出去给分半 OCR 用，避免调用方又拿回用户选的原始顺序
        effectiveTopPath: topPath,
        effectiveBottomPath: bottomPath,
      );
    } finally {
      // 原图位图很大，必须立刻还回去
      top.dispose();
      bottom.dispose();
    }
  }

  Future<Directory> _outputDir() async {
    final Directory base = outputDirOverride ??
        Directory('${(await getTemporaryDirectory()).path}/timetable_stitch');
    if (!await base.exists()) {
      await base.create(recursive: true);
    }
    return base;
  }

  /// 只读图片头拿到原始宽高 —— 不解码整张图，省内存
  Future<({int width, int height})> _sizeOf(String path) async {
    final Uint8List bytes = await File(path).readAsBytes();
    final ui.ImmutableBuffer buffer =
        await ui.ImmutableBuffer.fromUint8List(bytes);
    final ui.ImageDescriptor descriptor =
        await ui.ImageDescriptor.encoded(buffer);
    final ({int width, int height}) size =
        (width: descriptor.width, height: descriptor.height);
    descriptor.dispose();
    buffer.dispose();
    return size;
  }

  /// 降采样成"**窄但等高**"的小图 → 转"每行亮度向量"。
  ///
  /// ⚠️ [height] 必须传原始高度：横向缩、纵向不缩，这样一行特征正好对应
  /// 一个原始像素行（原因见 [_sampleColumns] 的说明）。`instantiateCodec`
  /// 同时给 targetWidth 和 targetHeight 时会按指定尺寸缩放、不保持比例 ——
  /// 这正是我们要的。
  Future<RowSignature> _signatureOf(
    String path, {
    required int width,
    required int height,
  }) async {
    final Uint8List bytes = await File(path).readAsBytes();
    final ui.ImmutableBuffer buffer =
        await ui.ImmutableBuffer.fromUint8List(bytes);
    final ui.ImageDescriptor descriptor =
        await ui.ImageDescriptor.encoded(buffer);
    final ui.Codec codec = await descriptor.instantiateCodec(
      targetWidth: width,
      targetHeight: height,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image small = frame.image;

    final ByteData? raw =
        await small.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) {
      small.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      throw StateError('读不到像素数据');
    }

    final Uint8List px =
        raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    final int w = small.width;
    final int h = small.height;
    final List<int> luma = List<int>.filled(w * h, 0);
    for (int i = 0; i < w * h; i++) {
      final int p = i * 4;
      // Rec.601 亮度。不转灰度直接比 RGB 也行，但行特征会变成 3 倍长、
      // 计算量翻三倍，而亮度已经够区分"这一行长什么样"了
      luma[i] = (px[p] * 299 + px[p + 1] * 587 + px[p + 2] * 114) ~/ 1000;
    }

    small.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();

    return RowSignature.fromLuminance(
      rowCount: h,
      columns: w,
      luminance: luma,
    );
  }

  Future<ui.Image> _decodeFull(String path) async {
    final Uint8List bytes = await File(path).readAsBytes();
    final ui.ImmutableBuffer buffer =
        await ui.ImmutableBuffer.fromUint8List(bytes);
    final ui.ImageDescriptor descriptor =
        await ui.ImageDescriptor.encoded(buffer);
    final ui.Codec codec = await descriptor.instantiateCodec();
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return image;
  }
}
