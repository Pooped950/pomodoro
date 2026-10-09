import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/ocr/timetable_grid.dart';

/// 课表表头的**模糊表述识别**（2026-10-09 用户明确要求）。
///
/// 用户原话：「要做好相关的模糊语言识别，比如 `10/9` 和 `10.9` 和 `10月九号`
/// 是一个东西，推演模拟一下相关表述，至少务必保证课程节数识别正确」。
///
/// 这里把**推演出来的所有写法**钉成测试 —— 以后加写法先在这里加一条，
/// 免得又出现「主流程认、兜底不认」那种改一处漏一处的事故。
void main() {
  group('日期：同一个日期的各种写法都要认', () {
    test('★ 数字 + 各种分隔符', () {
      for (final String s in <String>[
        '10/9',
        '10-9',
        '10.9',
        '10、9',
        '10,9',
        '10\\9',
        '10 / 9',
        '10月9',
      ]) {
        expect(looksLikeDateToken(s), isTrue, reason: '「$s」应该被认成日期');
      }
    });

    test('★ 中文月日', () {
      for (final String s in <String>[
        '10月9日',
        '10月9号',
        '10月09日',
        '10月九日',
        '10月九号',
        '九月九日',
        '九月九号',
        '9月9日',
      ]) {
        expect(looksLikeDateToken(s), isTrue, reason: '「$s」应该被认成日期');
      }
    });

    test('★ 只写日号（月份单独一行的那种）', () {
      for (final String s in <String>['9', '09', '9日', '9号', '九', '九日', '九号']) {
        expect(looksLikeDateToken(s), isTrue, reason: '「$s」应该被认成日期');
      }
    });

    test('★ 完整日期', () {
      for (final String s in <String>[
        '2026-10-09',
        '2026/10/9',
        '2026.10.9',
      ]) {
        expect(looksLikeDateToken(s), isTrue, reason: '「$s」应该被认成日期');
      }
    });

    test('★ 用户举的三个例子确实是「一个东西」', () {
      for (final String s in <String>['10/9', '10.9', '10月九号']) {
        expect(looksLikeDateToken(s), isTrue, reason: '「$s」应该被认成日期');
      }
    });

    test('★ 不是日期的东西必须排除', () {
      for (final String s in <String>[
        '第6周', // 周次
        '第 6 周',
        '第1节', // 节次
        '第12节',
        '08:00', // 时刻
        '08:00-08:50',
        '星期一',
        '周一',
        '',
        '   ',
        '材料力学', // 课名
      ]) {
        expect(looksLikeDateToken(s), isFalse, reason: '「$s」不是日期，不该认');
      }
    });
  });

  group('节次：各种写法都要能解析出正确的节号', () {
    test('★ 阿拉伯数字（可带「第…节」外壳）', () {
      expect(parsePeriodToken('1'), 1);
      expect(parsePeriodToken('01'), 1);
      expect(parsePeriodToken('13'), 13);
      expect(parsePeriodToken('第1节'), 1);
      expect(parsePeriodToken('第12节'), 12);
      expect(parsePeriodToken('第 12 节'), 12);
      expect(parsePeriodToken('1节'), 1);
    });

    test('★ 中文数字', () {
      expect(parsePeriodToken('一'), 1);
      expect(parsePeriodToken('二'), 2);
      expect(parsePeriodToken('九'), 9);
      expect(parsePeriodToken('十'), 10);
      expect(parsePeriodToken('十一'), 11);
      expect(parsePeriodToken('十二'), 12);
      expect(parsePeriodToken('二十'), 20);
      expect(parsePeriodToken('二十三'), 23);
      expect(parsePeriodToken('三十'), 30);
      expect(parsePeriodToken('第十节'), 10);
      expect(parsePeriodToken('第十二节'), 12);
    });

    test('★ 不是节次的东西必须排除', () {
      expect(parsePeriodToken('08:00'), isNull, reason: '时刻不是节次');
      expect(parsePeriodToken('第6周'), isNull, reason: '周次不是节次');
      expect(parsePeriodToken('10月9日'), isNull, reason: '日期不是节次');
      expect(parsePeriodToken('0'), isNull, reason: '节次从 1 开始');
      expect(parsePeriodToken('31'), isNull, reason: '超过 30 节不合理');
      expect(parsePeriodToken(''), isNull);
      expect(parsePeriodToken('材料力学'), isNull);
      expect(parsePeriodToken('二三'), isNull, reason: '「二三」不是合法数字');
    });
  });
}
