import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/widgets.dart' show Rect;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../domain/ocr/ocr_result.dart';
import '../../domain/ocr/timetable_grid.dart';

/// 离线文字识别 —— 课表导入（方案 A）。
///
/// 用 Google ML Kit 的**中文**识别器：
///   - 模型随 APK 打包，**完全离线**：不联网也能出结果 ——
///     这是"图片不用离开设备就有识别结果"的技术前提
///   - 必须显式指定中文脚本。默认的拉丁识别器识别汉字会输出一堆乱码，
///     而课表里的课程名 / 老师名 / 教室名几乎全是汉字
///
/// 返回结果保留每个文本行的坐标，理由见 [OcrBlock]。
class OcrService {
  const OcrService();

  Future<OcrResult> recognizeFile(String imagePath) async {
    final TextRecognizer recognizer =
        TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final RecognizedText recognized =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));

      final List<OcrBlock> blocks = <OcrBlock>[];
      for (final TextBlock block in recognized.blocks) {
        for (final TextLine line in block.lines) {
          final Rect box = line.boundingBox;
          // ⚠️ 连**词级坐标**一起带出来（2026-10-10）：跨列粘连行要按
          // "每个字属于哪一列"切分，只用整行的 left/right 就得靠"平均字宽"
          // 估算 —— 一行里汉字和数字混排时必然偏，切点跟着偏。
          // ML Kit 本来就给了，白丢可惜。详见 [OcrWord] 的注释。
          final List<OcrWord> words = <OcrWord>[
            for (final TextElement e in line.elements)
              OcrWord(
                text: e.text,
                left: e.boundingBox.left,
                top: e.boundingBox.top,
                right: e.boundingBox.right,
                bottom: e.boundingBox.bottom,
              ),
          ];
          blocks.add(
            OcrBlock(
              text: line.text,
              left: box.left,
              top: box.top,
              right: box.right,
              bottom: box.bottom,
              words: words,
            ),
          );
        }
      }

      return OcrResult(blocks: blocks, rawText: recognized.text);
    } finally {
      // 识别器持有原生资源，用完必须关
      await recognizer.close();
    }
  }

  /// 把拼图解码成原始像素，给**像素几何分析**用（课程块的行列范围量自
  /// 色块本身，比 OCR 文字坐标可信 —— 见 `timetable_geometry.dart`）。
  ///
  /// 解不开（文件坏了/格式不支持）返回 null，调用方退回纯文字路线。
  /// 1200×3154 的 RGBA 约 15MB，用完即弃，和拼图服务同一量级的开销。
  Future<TimetablePixels?> pixelsOf(String imagePath) async {
    ui.Image? image;
    try {
      final Uint8List bytes = await File(imagePath).readAsBytes();
      final ui.ImmutableBuffer buffer =
          await ui.ImmutableBuffer.fromUint8List(bytes);
      final ui.ImageDescriptor descriptor =
          await ui.ImageDescriptor.encoded(buffer);
      final ui.Codec codec = await descriptor.instantiateCodec();
      final ui.FrameInfo frame = await codec.getNextFrame();
      image = frame.image;

      final ByteData? raw =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (raw == null) {
        if (kDebugMode) debugPrint('[OCR] 像素读出失败（toByteData null）');
        return null;
      }
      if (kDebugMode) {
        debugPrint('[OCR] 像素就绪 ${image.width}x${image.height}');
      }
      return TimetablePixels(
        width: image.width,
        height: image.height,
        rgba: raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
      );
    } catch (e) {
      // 解不开不致命（退回纯文字路线），但 debug 下必须留痕 ——
      // 静默 null 会让人以为"算法不行"，其实是解码环境问题
      if (kDebugMode) debugPrint('[OCR] 像素解码失败：$e');
      return null;
    } finally {
      image?.dispose();
    }
  }
}
