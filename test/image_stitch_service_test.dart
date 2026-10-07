import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/data/services/image_stitch_service.dart';
import 'package:pomodoro/domain/ocr/image_stitcher.dart';

/// 拼图服务的**集成**测试 —— 真的解码、真的合成、真的落文件。
///
/// 和对缝算法（`image_stitcher_test.dart`）的分工：
///   - 那边测的是"数学对不对"，用假的亮度数组，不碰引擎
///   - 这边测的是"整条管子通不通"：PNG 进 → 解码 → 找重叠 → 画布合成 →
///     PNG 出。所以必须 `ensureInitialized()`，因为解码和 `Picture.toImage`
///     都走引擎，不是纯 Dart
///
/// 图片同样是**程序合成**的（真实截图带用户课程名，不进仓库）。
/// 合成图每 20 行一条随行号变化的色带，所以"哪一行是哪一行"是唯一确定的 ——
/// 可以断言拼出来的**高度精确等于原图**。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('stitch_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('自动对缝拼接', () {
    test('★ 上下两半能拼回原图：宽高对、重叠对', () async {
      const int width = 240;
      const int fullHeight = 600;
      const int topHeight = 400;
      const int bottomStart = 260; // 重叠 = 400 - 260 = 140 像素
      const int bottomHeight = fullHeight - bottomStart; // 340

      final ui.Image full = await _synthPage(width, fullHeight, seed: 1);
      await _writePng(full, '${tmp.path}/full.png');

      final ui.Image top = await _crop(full, 0, topHeight);
      final ui.Image bottom = await _crop(full, bottomStart, bottomHeight);
      await _writePng(top, '${tmp.path}/top.png');
      await _writePng(bottom, '${tmp.path}/bottom.png');
      full.dispose();
      top.dispose();
      bottom.dispose();

      final StitchOutcome? out = await ImageStitchService(
        outputDirOverride: tmp,
      ).stitchAuto(
        topPath: '${tmp.path}/top.png',
        bottomPath: '${tmp.path}/bottom.png',
      );

      expect(out, isNotNull, reason: '同一张图裁出来的两半，必须能拼上');

      // 重叠高度允许 ±3 像素：粗扫在 64 像素宽的图上定位，精修在 256 像素宽的
      // 图上取答案，换算回原图还剩下几像素的取整误差。三像素在 2400 像素高的
      // 截图上是 0.1%，既看不出来也不会切到字
      expect(out!.overlapPixels, closeTo(140, 3));
      expect(out.width, width);
      expect(out.height, fullHeight, reason: '拼出来的总高必须等于原图');

      final ({int width, int height}) written = await _pngSize(out.path);
      expect(written.width, width);
      expect(written.height, fullHeight, reason: '落盘的 PNG 尺寸也要对');

      expect(out.isConfident, isTrue);
    });

    test('★ 上下都有固定装饰时，能拼上、且下半段内容不丢（真机实测踩到的坑）',
        () async {
      const int width = 240;
      const int pageRows = 700;
      const int chromeTop = 40;
      const int chromeBottom = 50;
      const int contentRows = 300;
      const int scroll = 160;

      final ui.Image page = await _synthPage(width, pageRows, seed: 21);

      // 第一张：内容 0~299；第二张：内容 160~459
      final ui.Image top = await _shot(
        page,
        fromRow: 0,
        rows: contentRows,
        chromeTop: chromeTop,
        chromeBottom: chromeBottom,
        width: width,
      );
      final ui.Image bottom = await _shot(
        page,
        fromRow: scroll,
        rows: contentRows,
        chromeTop: chromeTop,
        chromeBottom: chromeBottom,
        width: width,
      );
      await _writePng(top, '${tmp.path}/s_top.png');
      await _writePng(bottom, '${tmp.path}/s_bottom.png');

      final StitchOutcome? out = await ImageStitchService(
        outputDirOverride: tmp,
      ).stitchAuto(
        topPath: '${tmp.path}/s_top.png',
        bottomPath: '${tmp.path}/s_bottom.png',
      );

      expect(
        out,
        isNotNull,
        reason: '两张图上下有重复的装饰，不该因此被判成"拼不上" —— '
            '这正是真机上遇到的情况',
      );
      expect(out!.chrome.top, greaterThan(0), reason: '应该认出顶部有固定装饰');

      // ★ 最要紧的一条：拼出来的内容区必须和原 page **逐行对上**。
      //
      //   上半张自己的底部导航栏要丢掉，下半张的内容接在"内容区末尾"后面 ——
      //   按整张图算的话，上半张的导航栏会留在中间、把下半张该接的那一段挤掉，
      //   表现就是"下半段课表全没了"（2026-10-06 真机实测第二次栽在这）
      final RowSignature stitched = await _sigOfFile(out.path);
      final RowSignature pageSig = await _sigOfImage(page);

      expect(stitched.rowCount, out.height);
      for (int j = 0; j + 20 <= contentRows + scroll; j += 20) {
        final double d = _rowDiffBetween(stitched, pageSig, chromeTop + j, j);
        expect(
          d,
          lessThan(8),
          reason: '拼出来的第 ${chromeTop + j} 行应该对应原图第 $j 行 —— '
              '差了就说明内容错位、或者被挤掉了',
        );
      }

      // 总高 = 上装饰 + 内容 + 滚动量 + 下装饰
      expect(
        out.height,
        closeTo(chromeTop + contentRows + scroll + chromeBottom, 12),
      );

      page.dispose();
      top.dispose();
      bottom.dispose();
    });

    test('★ 完全不重叠的两张图 → 返回 null，宁可不拼也不拼错', () async {
      final ui.Image a = await _synthPage(240, 300, seed: 11);
      final ui.Image b = await _synthPage(240, 300, seed: 99);
      await _writePng(a, '${tmp.path}/a.png');
      await _writePng(b, '${tmp.path}/b.png');
      a.dispose();
      b.dispose();

      final StitchOutcome? out = await ImageStitchService(
        outputDirOverride: tmp,
      ).stitchAuto(topPath: '${tmp.path}/a.png', bottomPath: '${tmp.path}/b.png');

      expect(out, isNull);
    });

    test('宽度不同的两张图直接放弃（拼了也没意义）', () async {
      final ui.Image a = await _synthPage(240, 300, seed: 5);
      final ui.Image b = await _synthPage(320, 300, seed: 5);
      await _writePng(a, '${tmp.path}/wide_a.png');
      await _writePng(b, '${tmp.path}/wide_b.png');
      a.dispose();
      b.dispose();

      final StitchOutcome? out = await ImageStitchService(
        outputDirOverride: tmp,
      ).stitchAuto(
        topPath: '${tmp.path}/wide_a.png',
        bottomPath: '${tmp.path}/wide_b.png',
      );

      expect(out, isNull);
    });
  });

  group('手动指定重叠高度', () {
    test('★ 用户手动填的重叠会被精确采用（不做二次猜测）', () async {
      final ui.Image full = await _synthPage(240, 600, seed: 7);
      final ui.Image top = await _crop(full, 0, 400);
      final ui.Image bottom = await _crop(full, 260, 340);
      await _writePng(top, '${tmp.path}/m_top.png');
      await _writePng(bottom, '${tmp.path}/m_bottom.png');
      full.dispose();
      top.dispose();
      bottom.dispose();

      final StitchOutcome out = await ImageStitchService(
        outputDirOverride: tmp,
      ).stitchWithOverlap(
        topPath: '${tmp.path}/m_top.png',
        bottomPath: '${tmp.path}/m_bottom.png',
        overlapPixels: 120,
      );

      expect(out.overlapPixels, 120, reason: '手动值必须原样采用，不能"帮用户改一下"');
      expect(out.height, 400 + 340 - 120);
      expect(out.match, isNull, reason: '手动拼接没有自动匹配信息');
    });

    test('重叠高度超过图高时被夹住，不崩', () async {
      final ui.Image full = await _synthPage(120, 200, seed: 3);
      final ui.Image top = await _crop(full, 0, 200);
      final ui.Image bottom = await _crop(full, 100, 100);
      await _writePng(top, '${tmp.path}/c_top.png');
      await _writePng(bottom, '${tmp.path}/c_bottom.png');
      full.dispose();
      top.dispose();
      bottom.dispose();

      final StitchOutcome out = await ImageStitchService(
        outputDirOverride: tmp,
      ).stitchWithOverlap(
        topPath: '${tmp.path}/c_top.png',
        bottomPath: '${tmp.path}/c_bottom.png',
        overlapPixels: 99999,
      );

      // 最多只能重叠到较矮那张的全部高度（100）
      expect(out.overlapPixels, 100);
      expect(out.height, 200);
    });
  });
}

// ----------------------------------------------------------------------

/// 合成一张"课表样式"的长图：白底 + 每 20 行一条随行号变化的色带。
///
/// [seed] 换一个值就是一张完全不同的图（用来造"两张不相干的图"这种局面）。
Future<ui.Image> _synthPage(int width, int height, {required int seed}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);

  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );

  for (int band = 0; band * 20 < height; band++) {
    final int mix = (band * 2654435761 + seed * 40503) & 0x7fffffff;
    final ui.Paint p = ui.Paint()
      ..color = ui.Color.fromARGB(
        255,
        30 + mix % 200,
        30 + (mix >> 8) % 200,
        30 + (mix >> 16) % 200,
      );
    final double y = (band * 20).toDouble();
    canvas.drawRect(ui.Rect.fromLTWH(10, y, (width - 20).toDouble(), 8), p);
    // 再来一个随行号变化的短块 —— 让每一行的纹理唯一，避免"错答案也很像"
    canvas.drawRect(
      ui.Rect.fromLTWH(20 + (mix >> 4) % (width - 60), y + 11, 30, 6),
      p,
    );
  }

  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

/// 从 [src] 的第 [fromY] 行起裁 [height] 行
Future<ui.Image> _crop(ui.Image src, int fromY, int height) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.drawImage(src, ui.Offset(0, -fromY.toDouble()), ui.Paint());
  final ui.Picture picture = recorder.endRecording();
  final ui.Image out = await picture.toImage(src.width, height);
  picture.dispose();
  return out;
}

/// 合成一张"手机截图"：`[顶部装饰][从 page 第 fromRow 行开始的内容][底部装饰]`
///
/// ## 这个 helper 是补上一次漏测的
///
/// 之前所有测试都是"纯内容的两半"，没画装饰。真机上截图**一定带装饰**：
/// 手机状态栏、应用自己的标题栏、底部导航栏 —— 它们在两张图里位置一模一样、
/// 不属于滚动内容。**测试没模拟这个前提，所以 bug 在测试里复现不出来。**
///
/// 顶部和底部**都要画**：底部那条会让"上半张的导航栏该不该保留"这个问题
/// 暴露出来（拼接要按内容区算，不是按整张图算）。
Future<ui.Image> _shot(
  ui.Image page, {
  required int fromRow,
  required int rows,
  required int chromeTop,
  required int chromeBottom,
  required int width,
}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);

  // 顶部装饰：固定的深色条 + 右上角一个亮块（时钟）
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), chromeTop.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF202020),
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(width - 60, 6, 44, 12),
    ui.Paint()..color = const ui.Color(0xFFE0E0E0),
  );

  canvas.drawImageRect(
    page,
    ui.Rect.fromLTWH(0, fromRow.toDouble(), width.toDouble(), rows.toDouble()),
    ui.Rect.fromLTWH(
      0,
      chromeTop.toDouble(),
      width.toDouble(),
      rows.toDouble(),
    ),
    ui.Paint(),
  );

  // 底部装饰：固定的一条浅色导航栏
  canvas.drawRect(
    ui.Rect.fromLTWH(
      0,
      (chromeTop + rows).toDouble(),
      width.toDouble(),
      chromeBottom.toDouble(),
    ),
    ui.Paint()..color = const ui.Color(0xFFF0F0F0),
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(
      width / 2 - 16,
      (chromeTop + rows + 10).toDouble(),
      32,
      12,
    ),
    ui.Paint()..color = const ui.Color(0xFFB0B0B0),
  );

  final ui.Picture picture = recorder.endRecording();
  final ui.Image out =
      await picture.toImage(width, chromeTop + rows + chromeBottom);
  picture.dispose();
  return out;
}

/// 把任意 [ui.Image] 转成"每行亮度向量"（和服务层同一套做法）
Future<RowSignature> _sigOfImage(ui.Image img, {int columns = 96}) async {
  final ByteData? raw =
      await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final Uint8List px =
      raw!.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
  final int w = img.width;
  final int h = img.height;
  final List<int> luma = List<int>.filled(w * h, 0);
  for (int i = 0; i < w * h; i++) {
    final int p = i * 4;
    luma[i] = (px[p] * 299 + px[p + 1] * 587 + px[p + 2] * 114) ~/ 1000;
  }
  // 横向降到 columns 列、纵向保持原始行数 —— 和服务层一致
  final int step = (w / columns).ceil();
  final int cols = (w / step).ceil();
  final List<int> out = List<int>.filled(h * cols, 0);
  for (int r = 0; r < h; r++) {
    for (int c = 0; c < cols; c++) {
      int sum = 0;
      int n = 0;
      for (int k = c * step; k < (c + 1) * step && k < w; k++) {
        sum += luma[r * w + k];
        n++;
      }
      out[r * cols + c] = n == 0 ? 0 : sum ~/ n;
    }
  }
  return RowSignature.fromLuminance(
    rowCount: h,
    columns: cols,
    luminance: out,
  );
}

/// 读一个 PNG 文件并转成行特征
Future<RowSignature> _sigOfFile(String path) async {
  final Uint8List bytes = await File(path).readAsBytes();
  final ui.ImmutableBuffer buffer =
      await ui.ImmutableBuffer.fromUint8List(bytes);
  final ui.ImageDescriptor d = await ui.ImageDescriptor.encoded(buffer);
  final ui.Codec codec = await d.instantiateCodec();
  final ui.FrameInfo f = await codec.getNextFrame();
  final ui.Image img = f.image;
  final RowSignature sig = await _sigOfImage(img);
  img.dispose();
  codec.dispose();
  d.dispose();
  buffer.dispose();
  return sig;
}

/// 两行之间的平均绝对亮度差
double _rowDiffBetween(RowSignature a, RowSignature b, int i, int j) {
  final int ab = i * a.columns;
  final int bb = j * b.columns;
  final int n = a.columns < b.columns ? a.columns : b.columns;
  int sum = 0;
  for (int c = 0; c < n; c++) {
    sum += (a.values[ab + c] - b.values[bb + c]).abs();
  }
  return sum / n;
}

Future<void> _writePng(ui.Image image, String path) async {
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  expect(data, isNotNull);
  await File(path).writeAsBytes(
    data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

/// 只读 PNG 头拿宽高（不解码整张图）
Future<({int width, int height})> _pngSize(String path) async {
  final Uint8List bytes = await File(path).readAsBytes();
  final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(buffer);
  final ({int width, int height}) size =
      (width: descriptor.width, height: descriptor.height);
  descriptor.dispose();
  buffer.dispose();
  return size;
}
