import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/data/services/image_stitch_service.dart';

/// 上下两页**选反了**时的回归（2026-10-09 用户报的 bug）。
///
/// ## Bug 现象
///
/// 用户把"下页"选进上格、"上页"选进下格 → 拼图**看着是对的**（算法自动
/// 换过来了），但识别结果一塌糊涂。
///
/// ## 根因
///
/// `stitchAuto` 内部发现反了会**交换两张图再拼**，`dstY` / `srcTop` 也是按
/// 交换后的几何算的。但 `StitchOutcome` 当时**没把交换后的路径带出来**，
/// 调用方（导入页）就还拿"用户选的原始顺序"去分别 OCR ——
/// **几何按 A 算、图片是 B 的顺序**，坐标映射全乱。
///
/// ## 钉住什么
///
/// `effectiveTopPath` / `effectiveBottomPath` 必须是**真正用于拼接的那两条**，
/// 正着传时等于原参数，反着传时是交换后的。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('stitch_test_');
    // `_outputDir()` 走 path_provider，测试环境没有原生实现 → 直接给个临时目录
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => dir.path,
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  /// 造一张"每行颜色都不同"的条纹图 —— 颜色就是行号，拼接算法认的就是这个。
  ///
  /// ⚠️ 颜色必须用**散列**而不是 `r % 256` 这种线性映射：线性映射周期太强，
  /// 任何位移都能凑出一个"看着还行"的假匹配，测出来的 `swapped` 全是错的。
  Future<String> stripe(
    String name,
    int firstRow,
    int rows, {
    int topChrome = 0,
    int bottomChrome = 0,
  }) async {
    const int w = 400;
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas canvas = Canvas(rec);
    final Paint p = Paint();
    for (int i = 0; i < rows; i++) {
      final int r = firstRow + i;
      final int h = (r * 2654435761) & 0xFFFFFFFF;
      p.color = Color.fromARGB(
          255, (h >> 16) & 0xFF, (h >> 8) & 0xFF, h & 0xFF);
      canvas.drawRect(Rect.fromLTWH(0, i.toDouble(), w.toDouble(), 1), p);
    }
    // 顶部/底部固定装饰：整块纯色（不随滚动变化）
    p.color = const Color(0xFF202020);
    if (topChrome > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), topChrome.toDouble()), p);
    }
    if (bottomChrome > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, (rows - bottomChrome).toDouble(), w.toDouble(),
            bottomChrome.toDouble()),
        p,
      );
    }
    final ui.Image img = await rec.endRecording().toImage(w, rows);
    final ByteData? bd = await img.toByteData(format: ui.ImageByteFormat.png);
    final File f = File('${dir.path}/$name');
    await f.writeAsBytes(bd!.buffer.asUint8List());
    return f.path;
  }

  test('★ 正着传：effective 路径就是原参数', () async {
    // 上页含第 0~59 行，下页含第 40~99 行 → 重叠 40~59
    final String top = await stripe('f_top.png', 0, 60, topChrome: 6);
    final String bottom = await stripe('f_bottom.png', 40, 60, bottomChrome: 6);

    final StitchOutcome? st = await const ImageStitchService()
        .stitchAuto(topPath: top, bottomPath: bottom);
    expect(st, isNotNull, reason: '这两张有 20 行重叠，应该能拼上');
    expect(st!.swapped, isFalse);
    expect(st.effectiveTopPath, top);
    expect(st.effectiveBottomPath, bottom);
  });

  test('★ 反着传：effective 路径必须是**交换后**的', () async {
    // 故意反着传：把"下页"当 top、"上页"当 bottom
    final String realTop = await stripe('r_top.png', 0, 60, topChrome: 6);
    final String realBottom =
        await stripe('r_bottom.png', 40, 60, bottomChrome: 6);

    final StitchOutcome? st = await const ImageStitchService()
        .stitchAuto(topPath: realBottom, bottomPath: realTop);

    expect(st, isNotNull);
    expect(st!.swapped, isTrue, reason: '算法应该认出用户选反了');

    // ⚠️ 这就是本 bug 的核心断言：分半 OCR 必须按**交换后**的顺序喂图，
    // 否则「几何按 A 算、图片是 B 的顺序」，识别结果全乱
    expect(st.effectiveTopPath, realTop,
        reason: '反着传时 effectiveTopPath 应该是真正在上面的那张');
    expect(st.effectiveBottomPath, realBottom,
        reason: '反着传时 effectiveBottomPath 应该是真正在下面的那张');
  });

  test('★ effective 路径永远不为空（调用方能安全兜底）', () async {
    final String top = await stripe('e_top.png', 0, 60, topChrome: 6);
    final String bottom = await stripe('e_bottom.png', 40, 60, bottomChrome: 6);
    final StitchOutcome? st = await const ImageStitchService()
        .stitchAuto(topPath: top, bottomPath: bottom);
    expect(st!.effectiveTopPath, isNotEmpty);
    expect(st.effectiveBottomPath, isNotEmpty);
  });
}
