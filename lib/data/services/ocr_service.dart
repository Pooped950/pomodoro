import 'package:flutter/widgets.dart' show Rect;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../domain/ocr/ocr_result.dart';

/// 离线文字识别 —— 课表导入（方案 A）。
///
/// 用 Google ML Kit 的**中文**识别器：
///   - 模型随 APK 打包，**完全离线**，不联网、不上传图片 ——
///     与产品「本地存储，不联网，不收集任何数据」的原则一致
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
          blocks.add(
            OcrBlock(
              text: line.text,
              left: box.left,
              top: box.top,
              right: box.right,
              bottom: box.bottom,
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
}
