import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/timetable/course.dart';

/// 课表页的**编辑**与**显示**（2026-10-10 用户反馈）。
///
/// 用户原话：「课表导入以后的单节课没办法调整位置和内容，
/// 并且识别出来以后课表里教室显示不全，重新排版一下」。
void main() {
  group('教室名的显示形态', () {
    test('★ 剥掉导入留下的 `@` 前缀（用户报的"显示不全"主因）', () {
      // `@` 是识别阶段的分隔记号，画在格子里纯属占地方 ——
      // 窄格子本来就放不下几个字，少一个字符常常就是"能不能看全"的差别
      // ⚠️ 2026-10-10 起显示层还会**紧凑化**：结尾的「教室」两个字去掉
      // （格子位置本身就说明了），免得 12 字的长教室名被 ellipsis 截掉房间号
      expect(courseLocationForDisplay('@腾龙楼408教室'), '腾龙楼408');
      expect(courseLocationForDisplay('@至善楼206教室'), '至善楼206');
      expect(courseLocationForDisplay('@文渊楼211教室'), '文渊楼211');
    });

    test('★ 连续的多个 `@` 也要剥干净', () {
      expect(courseLocationForDisplay('@@腾龙楼408教室'), '腾龙楼408');
      expect(courseLocationForDisplay('  @  腾龙楼408  '), '腾龙楼408');
    });

    test('★ 没有前缀的原样返回', () {
      expect(courseLocationForDisplay('腾龙楼408教室'), '腾龙楼408');
      expect(courseLocationForDisplay(''), '');
      expect(courseLocationForDisplay('   '), '');
    });

    test('★ 中间的 `@` 不能动（有些教室名真带 @）', () {
      expect(courseLocationForDisplay('机房@A-101'), '机房@A-101');
      expect(courseLocationForDisplay('实验楼@3层'), '实验楼@3层');
    });
  });

  group('Course.copyWith：编辑要能改全部字段', () {
    final Course base = Course(
      id: 7,
      weekday: 3,
      startPeriod: 5,
      endPeriod: 6,
      name: '原课名',
      location: '@原教室101',
      colorIndex: 2,
      createdAt: DateTime(2026, 10, 1),
    );

    test('★ 改内容（课名 / 教室）', () {
      final Course c = base.copyWith(name: '新课件', location: '@新教室202');
      expect(c.name, '新课件');
      expect(c.location, '@新教室202');
      expect(c.id, 7, reason: '改内容不该换 id');
    });

    test('★ 挪位置（星期 / 起止节次）', () {
      final Course c = base.copyWith(weekday: 5, startPeriod: 9, endPeriod: 10);
      expect(c.weekday, 5);
      expect(c.startPeriod, 9);
      expect(c.endPeriod, 10);
      expect(c.name, '原课名', reason: '挪位置不该动课名');
    });

    test('★ 内容和位置一起改', () {
      final Course c = base.copyWith(
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
        name: '换课了',
        location: '@别处301',
      );
      expect(c.weekday, 1);
      expect(c.startPeriod, 1);
      expect(c.endPeriod, 2);
      expect(c.name, '换课了');
      expect(c.location, '@别处301');
      expect(c.colorIndex, 2, reason: '颜色不该被编辑带跑');
    });

    test('★ 不传参数时原样返回', () {
      final Course c = base.copyWith();
      expect(c.name, base.name);
      expect(c.weekday, base.weekday);
      expect(c.startPeriod, base.startPeriod);
      expect(c.endPeriod, base.endPeriod);
      expect(c.location, base.location);
    });
  });
}
