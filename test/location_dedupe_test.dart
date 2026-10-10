import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/timetable/course.dart';

/// 教室名**拼重复**的清理（2026-10-10 真机实测）。
///
/// ## 怎么发现的
///
/// 用户报「识别出来以后课表里教室显示不全」，拉真机数据库一看 ——
/// **11 门课里 10 门的教室名是坏的**：
///
/// ```
/// '桃花坪三教桃花坪三教210教室'                    ← 整段重复
/// '树达楼桃花坪树达楼307教室'                      ← 楼栋名重复
/// '桃花坪四教(实训楼)花坪四教(实训楼)304教室'        ← 尾部重叠（少一个字）
/// '1桃花坪一教(达善楼)桃花坪一教(达善楼)A02A04'      ← 整段重复
/// ```
///
/// 根因：这款 App 的教室名很长，OCR 把相邻两列粘成**跨列行**，
/// 拆分时切点偏了 → 前半段楼栋名和后半段完整教室名叠在一起。
///
/// 下面的用例**全部来自真机数据**（已脱敏：楼名按 `AI交接文档.md`
/// 的映射换过，但结构和长度保留）。
void main() {
  group('★ 真机上抓到的脏数据（逐条来自数据库）', () {
    test('整段重复', () {
      expect(dedupeLocationPrefix('桃花坪三教桃花坪三教210教室'),
          '桃花坪三教210教室');
      expect(dedupeLocationPrefix('桃花坪四教(实训楼)桃花坪四教(实训楼)202数室'),
          '桃花坪四教(实训楼)202数室');
    });

    test('楼栋名重复（前半是"楼栋+校区"，后半才是房间）', () {
      expect(dedupeLocationPrefix('树达楼桃花坪树达楼307教室'), '树达楼307教室');
      expect(dedupeLocationPrefix('树达楼桃花坪树达楼406教室'), '树达楼406教室');
      expect(dedupeLocationPrefix('树达楼桃花坪树达楼桃506教室'), '树达楼桃506教室');
      expect(dedupeLocationPrefix('树达楼桃花坪树达楼307教'), '树达楼307教');
    });

    test('尾部重叠（重复的那段少一两个字）', () {
      expect(dedupeLocationPrefix('桃花坪四教(实训楼)花坪四教(实训楼)304教室'),
          '桃花坪四教(实训楼)304教室');
    });

    test('带前缀杂字的整段重复', () {
      expect(
        dedupeLocationPrefix('1桃花坪一教(达善楼)桃花坪一教(达善楼)A02A04406、410机房'),
        '1桃花坪一教(达善楼)A02A04406、410机房',
      );
    });
  });

  group('⚠️ 正常数据绝不能改坏', () {
    test('★ 干净的真实教室名原样返回', () {
      for (final String s in <String>[
        '桃花坪四教(实训楼)304教室',
        '至善楼206教室',
        '腾龙楼408教室',
        '文渊楼211教室',
        '至善楼117敦', // OCR 认错字但结构正常，不归这里管
        'A栋A101',
        '综合楼201',
      ]) {
        expect(dedupeLocationPrefix(s), s, reason: '「$s」是干净的，不该动');
      }
    });

    test('★ 两个并列地点不能误合并', () {
      // `桃花坪四教(实训楼)桃花坪篮球场` —— 后半段没有房间号，
      // 说明这是"两个地点"而不是"重复的楼栋名"
      const String s = '桃花坪四教(实训楼)桃花坪篮球场';
      expect(dedupeLocationPrefix(s), s);
    });

    test('★ 太短的串直接放过', () {
      for (final String s in <String>['101', '教2-213', 'A101', '']) {
        expect(dedupeLocationPrefix(s), s);
      }
    });
  });

  group('显示形态（剥 @ + 去重）', () {
    test('★ 老数据：既带 @ 又拼重复，显示时要一并清掉', () {
      expect(courseLocationForDisplay('@桃花坪三教桃花坪三教210教室'),
          '桃花坪三教210');
      expect(courseLocationForDisplay('@树达楼桃花坪树达楼307教室'),
          '树达楼307');
    });

    test('★ 新数据：剥 @ + 紧凑化', () {
      expect(courseLocationForDisplay('@至善楼206教室'), '至善楼206');
    });

    test('★ 中间的 @ 不动', () {
      expect(courseLocationForDisplay('机房@A-101'), '机房@A-101');
    });
  });
}
