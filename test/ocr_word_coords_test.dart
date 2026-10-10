import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/ocr/ocr_result.dart';
import 'package:pomodoro/domain/ocr/timetable_grid.dart';

/// **词级坐标**（ML Kit 的 `TextElement`）展开成逐字符中心。
///
/// ## 背景（2026-10-10 真机实测）
///
/// 跨列粘连行要按"每个字属于哪一列"切分，而 `OcrBlock` 只有**整行**的
/// `left`/`right` —— 以前只能按**平均字宽**估算每个字的位置。
/// 一行里**汉字和数字混排**时（数字只有汉字一半宽）估算必然偏，
/// 切点跟着偏，**前一列的尾巴被切给后一列**。真机上的表现是教室名
/// 开头多出杂字：
///
/// ```
/// '室A(-)树达楼桃花坪树达楼307教室'   ← `室A(-)` 是别的格的尾巴
/// '1桃花坪一教(达善楼)A02A04…'        ← 开头多一个 `1`
/// ```
///
/// 修法：`OcrService` 把 `TextLine.elements` 一起带出来（以前丢掉了），
/// `_splitSpanningLine` 优先用这些**真实坐标**（见 [charCentersFromWords]）。
///
/// ⚠️ 这个函数只在**像素路线**里被用到 —— 纯文字路线不做跨列拆分。
/// 所以这里直接单测函数本身，不去构造复杂的像素夹具。
OcrBlock bw(
  double l,
  double t,
  double r,
  double bo,
  String text,
  List<(String, double, double)> words,
) =>
    OcrBlock(
      text: text,
      left: l,
      top: t,
      right: r,
      bottom: bo,
      words: <OcrWord>[
        for (final (String w, double wl, double wr) in words)
          OcrWord(text: w, left: wl, top: t, right: wr, bottom: bo),
      ],
    );

/// 把字符串拆成字符列表（和 `_splitSpanningLine` 的口径一致：剔除空白）
List<String> charsOf(String s) =>
    s.split('').where((String c) => c.trim().isNotEmpty).toList();

void main() {
  group('★ 有词级坐标：按真实位置展开', () {
    test('单个词：在它自己的框里均分', () {
      final OcrBlock b = bw(100, 0, 260, 30, '枫林楼301教室',
          <(String, double, double)>[('枫林楼301教室', 100, 260)]);
      final List<String> chars = charsOf('枫林楼301教室'); // 8 字
      final List<double>? c = charCentersFromWords(b, chars);

      expect(c, isNotNull);
      expect(c!.length, 8);
      // 8 个字均分 160px 宽 → 每字 20px，中心依次 110 / 130 / … / 250
      expect(c.first, closeTo(110, 0.01));
      expect(c.last, closeTo(250, 0.01));
      for (int i = 1; i < c.length; i++) {
        expect(c[i], greaterThan(c[i - 1]), reason: '字符顺序不能乱');
      }
    });

    test('★ 多个词：每个词用**自己的框**，不受别的词影响', () {
      final OcrBlock b = bw(
        40, 0, 380, 30,
        '枫林楼301教室 紫荆楼A02A04406教室',
        <(String, double, double)>[
          ('枫林楼301教室', 40, 200),
          ('紫荆楼A02A04406教室', 220, 380),
        ],
      );
      final List<String> chars = charsOf('枫林楼301教室紫荆楼A02A04406教室');
      final List<double>? c = charCentersFromWords(b, chars);

      expect(c, isNotNull);
      expect(c!.length, chars.length);

      // 第一个词的 8 个字都落在 [40, 200]
      for (int i = 0; i < 8; i++) {
        expect(c[i], greaterThanOrEqualTo(40));
        expect(c[i], lessThanOrEqualTo(200));
      }
      // 第二个词的字都落在 [220, 380]
      for (int i = 8; i < c.length; i++) {
        expect(c[i], greaterThanOrEqualTo(220));
        expect(c[i], lessThanOrEqualTo(380));
      }
    });

    test('★ 汉字+数字混排：按真实框算，不会像"平均字宽"那样偏', () {
      // 左边的词 8 个字占 160px（20px/字），右边的词 14 个字也占 160px
      // （约 11.4px/字）—— 两个词的**字宽差近一倍**。
      // 按整行平均（22 字 / 340px ≈ 15.5px/字）估算的话，
      // 右边第一个字会被算在 40 + 8×15.5 ≈ 164 —— 还落在左边词的范围内！
      // 用真实框就不会。
      final OcrBlock b = bw(
        40, 0, 380, 30,
        '枫林楼301教室 紫荆楼A02A04406教室',
        <(String, double, double)>[
          ('枫林楼301教室', 40, 200),
          ('紫荆楼A02A04406教室', 220, 380),
        ],
      );
      final List<String> chars = charsOf('枫林楼301教室紫荆楼A02A04406教室');
      final List<double> c = charCentersFromWords(b, chars)!;

      expect(c[8], greaterThan(220),
          reason: '第二个词的首字必须落在它自己的框里（220 之后），'
              '按平均字宽估算会把它算到 164 左右 —— 这就是真机上'
              '前一列的尾巴被切给后一列的机理');
    });
  });

  group('⚠️ 拿不到词级坐标时安全退回', () {
    test('★ 没有 words → 返回 null（调用方退回估算）', () {
      final OcrBlock b = OcrBlock(
          text: '枫林楼301教室', left: 40, top: 0, right: 200, bottom: 30);
      expect(charCentersFromWords(b, charsOf('枫林楼301教室')), isNull);
    });

    test('★ 空字符列表 → 返回 null', () {
      final OcrBlock b = bw(40, 0, 200, 30, '',
          <(String, double, double)>[('枫林楼301教室', 40, 200)]);
      expect(charCentersFromWords(b, <String>[]), isNull);
    });

    test('★ 展开出来的字符数和行文本对不上 → 返回 null（不硬套）', () {
      // OCR 的词切分和我们的字符切分不一致 —— 硬套会错位，
      // 必须检测出来并退回估算
      final OcrBlock b = bw(40, 0, 200, 30, '枫林楼301教室',
          <(String, double, double)>[('完全不对的词', 40, 200)]);
      expect(charCentersFromWords(b, charsOf('枫林楼301教室')), isNull);
    });

    test('★ 词里的空白不参与计数（口径要和 chars 一致）', () {
      final OcrBlock b = bw(40, 0, 200, 30, '枫林楼 301教室',
          <(String, double, double)>[('枫林楼 301教室', 40, 200)]);
      final List<String> chars = charsOf('枫林楼301教室'); // 8 字
      final List<double>? c = charCentersFromWords(b, chars);
      expect(c, isNotNull, reason: '词里的空白应该被跳过，长度要对得上');
      expect(c!.length, 8);
    });
  });
}
