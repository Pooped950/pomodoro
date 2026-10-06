import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/ocr/ocr_result.dart';

/// OCR 结果处理的单测（课表方案 A 阶段一）。
///
/// 重点测「阅读顺序」—— 它是后续把文本块还原成「节次 × 星期」网格的基础。
void main() {
  OcrBlock b(String text, double left, double top,
          {double w = 60, double h = 20}) =>
      OcrBlock(
        text: text,
        left: left,
        top: top,
        right: left + w,
        bottom: top + h,
      );

  group('inReadingOrder 阅读顺序', () {
    test('空列表 → 空', () {
      expect(inReadingOrder(<OcrBlock>[]), isEmpty);
    });

    test('单块原样返回', () {
      final List<OcrBlock> r = inReadingOrder(<OcrBlock>[b('A', 10, 10)]);
      expect(r.single.text, 'A');
    });

    test('不同行：从上到下', () {
      final List<OcrBlock> r = inReadingOrder(<OcrBlock>[
        b('第二行', 10, 100),
        b('第一行', 10, 10),
      ]);
      expect(r.map((OcrBlock e) => e.text).toList(), <String>['第一行', '第二行']);
    });

    test('★ 同一行内：从左到右（即使输入顺序是反的）', () {
      final List<OcrBlock> r = inReadingOrder(<OcrBlock>[
        b('右', 300, 10),
        b('左', 10, 10),
        b('中', 150, 10),
      ]);
      expect(r.map((OcrBlock e) => e.text).toList(), <String>['左', '中', '右']);
    });

    test('★ 同一行上下差几个像素仍算同一行（容差生效）', () {
      // 中心线差 6px，块高 20 → 容差 10，应归为同一行
      final List<OcrBlock> r = inReadingOrder(<OcrBlock>[
        b('右', 300, 12),
        b('左', 10, 6),
      ]);
      expect(r.map((OcrBlock e) => e.text).toList(), <String>['左', '右']);
    });

    test('★ 超过容差就分行（不能把相邻两行糊成一行）', () {
      // 中心线差 40px，块高 20 → 容差 10，必须分成两行
      final List<OcrBlock> r = inReadingOrder(<OcrBlock>[
        b('第二行', 10, 40),
        b('第一行', 10, 0),
      ]);
      expect(r.map((OcrBlock e) => e.text).toList(), <String>['第一行', '第二行']);
    });

    test('多行多列的整体顺序', () {
      // 布局：
      //   1(10,0)    2(300,0)
      //   4(10,100)  3(300,100)
      // 阅读顺序 = 第一行左→右，再第二行左→右 → 1,2,4,3
      final List<OcrBlock> r = inReadingOrder(<OcrBlock>[
        b('3', 300, 100),
        b('1', 10, 0),
        b('4', 10, 100),
        b('2', 300, 0),
      ]);
      expect(
        r.map((OcrBlock e) => e.text).toList(),
        <String>['1', '2', '4', '3'],
      );
    });

    test('容差按块高中位数自适应（大图小图都能用）', () {
      // 高 100 的大块：容差 50，差 40 仍算同一行
      final List<OcrBlock> r = inReadingOrder(<OcrBlock>[
        b('右', 500, 40, w: 200, h: 100),
        b('左', 10, 0, w: 200, h: 100),
      ]);
      expect(r.map((OcrBlock e) => e.text).toList(), <String>['左', '右']);
    });

    test('不修改传入的列表（纯函数）', () {
      final List<OcrBlock> input = <OcrBlock>[
        b('B', 300, 10),
        b('A', 10, 10),
      ];
      final List<String> before =
          input.map((OcrBlock e) => e.text).toList();
      inReadingOrder(input);
      expect(input.map((OcrBlock e) => e.text).toList(), before);
    });
  });

  group('OcrResult.debugDump', () {
    test('带坐标、按阅读顺序输出，便于复制出去设计解析规则', () {
      const OcrResult r = OcrResult(
        blocks: <OcrBlock>[],
        rawText: '',
      );
      expect(r.debugDump, '');

      final OcrResult r2 = OcrResult(
        blocks: <OcrBlock>[b('语文', 10, 10), b('数学', 100, 10)],
        rawText: '语文 数学',
      );
      final List<String> lines = r2.debugDump.trim().split('\n');
      expect(lines.length, 2);
      expect(lines[0], contains('语文'));
      expect(lines[0], contains('[10,10-'));
      expect(lines[1], contains('数学'));
    });
  });
}
