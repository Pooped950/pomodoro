import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/timetable/course.dart';
import 'package:pomodoro/domain/timetable/period_time.dart';

/// 课表时间轴与课程模型的回归测试。
///
/// 这两块都是**纯函数**，所以能在宿主机上把规则钉死 ——
/// 时间轴算错会让整张课表的时间都不对，是必须单测的部分。
void main() {
  group('按锚点排节次时间表', () {
    // 一份典型的中学课表：上午 4 节 8:00~11:40，下午 4 节 14:00~17:30，
    // 每节 45 分钟，晚上还有晚自习
    const ScheduleAnchors anchors = ScheduleAnchors(
      firstStartMinute: 8 * 60,
      morningEndMinute: 11 * 60 + 40,
      afternoonStartMinute: 14 * 60,
      lastEndMinute: 17 * 60 + 30,
      periodMinutes: 45,
      morningPeriodCount: 4,
      afternoonPeriodCount: 4,
      eveningStartMinute: 19 * 60,
      eveningEndMinute: 21 * 60 + 30,
    );

    test('节次从 1 连续排到 8，不多不少', () {
      final TimetableSchedule s = buildSchedule(anchors);
      expect(s.periods.length, 8);
      for (int i = 0; i < 8; i++) {
        expect(s.periods[i].period, i + 1);
      }
    });

    test('★ 两个锚点被钉死：上午最后一节结束 = 11:40，下午第一节开始 = 14:00', () {
      final TimetableSchedule s = buildSchedule(anchors);

      expect(s.forPeriod(4)!.endMinute, 11 * 60 + 40,
          reason: '"上午最后一节几点结束"是用户最确定的信息，不能被取整漂掉');
      expect(s.forPeriod(5)!.startMinute, 14 * 60,
          reason: '"下午第一节几点开始"同理');
    });

    test('★ 上午和下午之间是午休，不会被均匀排掉', () {
      final TimetableSchedule s = buildSchedule(anchors);
      final int lunch = s.forPeriod(5)!.startMinute - s.forPeriod(4)!.endMinute;

      // 11:40 → 14:00 是 140 分钟；如果午休被"均匀"摊掉，这里会变成十几分钟
      expect(lunch, 140);
      expect(lunch, greaterThan(60), reason: '午休被吃掉的话，下午的课会全排到中午去');
    });

    test('节次之间不重叠，且首尾接上最早 / 最晚', () {
      final TimetableSchedule s = buildSchedule(anchors);

      expect(s.periods.first.startMinute, 8 * 60);
      expect(s.periods.last.endMinute, 17 * 60 + 30);

      for (int i = 1; i < s.periods.length; i++) {
        expect(
          s.periods[i].startMinute,
          greaterThanOrEqualTo(s.periods[i - 1].endMinute),
          reason: '第 ${i + 1} 节和上一节时间重叠了',
        );
      }
    });

    test('每节时长默认就是用户填的那个（末节因钉锚点可能差几分钟）', () {
      final TimetableSchedule s = buildSchedule(anchors);
      for (int i = 0; i < 3; i++) {
        expect(s.periods[i].durationMinutes, 45);
      }
      expect(s.periods[4].durationMinutes, 45);
    });

    test('晚自习是一整块，不分节', () {
      final TimetableSchedule s = buildSchedule(anchors);
      expect(s.evening, isNotNull);
      expect(s.evening!.startMinute, 19 * 60);
      expect(s.evening!.endMinute, 21 * 60 + 30);
      expect(s.evening!.durationMinutes, 150);
    });

    test('没有晚自习时 evening 为 null', () {
      const ScheduleAnchors noEvening = ScheduleAnchors(
        firstStartMinute: 480,
        morningEndMinute: 700,
        afternoonStartMinute: 840,
        lastEndMinute: 1050,
        periodMinutes: 45,
        morningPeriodCount: 4,
        afternoonPeriodCount: 4,
      );
      expect(buildSchedule(noEvening).evening, isNull);
    });

    test('节数填 0 时不崩，只是没课', () {
      const ScheduleAnchors empty = ScheduleAnchors(
        firstStartMinute: 480,
        morningEndMinute: 700,
        afternoonStartMinute: 840,
        lastEndMinute: 1050,
        periodMinutes: 45,
        morningPeriodCount: 0,
        afternoonPeriodCount: 0,
      );
      final TimetableSchedule s = buildSchedule(empty);
      expect(s.periods, isEmpty);
      expect(s.isEmpty, isTrue);
    });

    test('只填 1 节也能排（不除零）', () {
      const ScheduleAnchors one = ScheduleAnchors(
        firstStartMinute: 480,
        morningEndMinute: 525,
        afternoonStartMinute: 840,
        lastEndMinute: 885,
        periodMinutes: 45,
        morningPeriodCount: 1,
        afternoonPeriodCount: 1,
      );
      final TimetableSchedule s = buildSchedule(one);
      expect(s.periods.length, 2);
      expect(s.periods[0].durationMinutes, 45);
    });

    test('★ 锚点装不下这些课时，宁可越过锚点也不排出倒挂的节次', () {
      // 2026-10-07 真机实测：识别把上午数成 6 节，用户填的"上午最后一节
      // 结束 11:40"装不下 6×45，旧逻辑钉锚点排出「第6节 11:45~11:40」
      const ScheduleAnchors tight = ScheduleAnchors(
        firstStartMinute: 480,
        morningEndMinute: 700, // 只装得下 4 节半
        afternoonStartMinute: 840,
        lastEndMinute: 1050,
        periodMinutes: 45,
        morningPeriodCount: 6,
        afternoonPeriodCount: 5,
      );
      final TimetableSchedule s = buildSchedule(tight);
      for (final PeriodTime p in s.periods) {
        expect(p.endMinute, greaterThan(p.startMinute),
            reason: '第 ${p.period} 节倒挂了（结束早于开始）');
      }
      // 课间被挤成 0 也要保住"下一节不早于上一节结束"
      for (int i = 1; i < s.periods.length; i++) {
        expect(s.periods[i].startMinute,
            greaterThanOrEqualTo(s.periods[i - 1].endMinute));
      }
    });
  });

  group('解析粘贴的官方作息表', () {
    test('★ Excel 复制的一整行（制表符分隔）解析出 13 节', () {
      // 学校作息表最常见的形态：一行里 13 个「HH:MM ~ HH:MM」，Tab 分隔
      const String excel = '08:00 ~ 08:45\t08:55 ~ 09:40\t10:00 ~ 10:45\t'
          '10:55 ~ 11:40\t12:45 ~ 13:30\t13:30 ~ 14:15\t14:30 ~ 15:15\t'
          '15:25 ~ 16:10\t16:30 ~ 17:15\t17:25 ~ 18:10\t19:00 ~ 19:45\t'
          '19:55 ~ 20:40\t20:50 ~ 21:35';
      final List<PeriodTime>? periods = parsePeriodTable(excel);
      expect(periods, isNotNull);
      expect(periods!.length, 13);
      expect(periods[0].startMinute, 480);
      expect(periods[0].endMinute, 525);
      // 第 5~6 节之间是 0 分钟（真实作息就是不均匀的）
      expect(periods[5].startMinute, periods[4].endMinute);
      expect(periods[4].startMinute, 12 * 60 + 45);
      expect(periods[12].endMinute, 21 * 60 + 35);
      for (int i = 0; i < 13; i++) {
        expect(periods[i].period, i + 1);
      }
    });

    test('一行一条、带节次号、横线连接也能认', () {
      final List<PeriodTime>? periods = parsePeriodTable('''
第1节 8:00-8:45
第2节 8:55-9:40
第3节 10:00-10:45
''');
      expect(periods, isNotNull);
      expect(periods!.length, 3);
      expect(periods[1].startMinute, 8 * 60 + 55);
    });

    test('认不出（太短 / 时间倒挂 / 乱序）返回 null，不硬排', () {
      expect(parsePeriodTable('08:00 ~ 08:45'), isNull, reason: '只有一对');
      expect(parsePeriodTable(''), isNull);
      expect(parsePeriodTable('10:00 ~ 09:00\n11:00 ~ 12:00'), isNull,
          reason: '结束早于开始');
      expect(
        parsePeriodTable('14:00 ~ 14:45\n08:00 ~ 08:45'),
        isNull,
        reason: '官方表不会倒着排，乱序说明粘错了内容',
      );
    });
  });

  group('从节次栏 y 锚点找午休', () {
    test('★ 明显的大间隔被认成午休，切在正确的位置', () {
      // 8 个节次锚点，第 4~5 节之间是午休（290 vs 常规 70）
      const List<double> ys = <double>[100, 170, 240, 310, 600, 670, 740, 810];
      expect(morningPeriodCountFromAnchors(ys), 4);
    });

    test('★ 间隔均匀时**不切** —— 随手切一刀会把下午的课误判成上午', () {
      const List<double> ys = <double>[100, 170, 240, 310, 380, 450];
      expect(morningPeriodCountFromAnchors(ys), 6);
    });

    test('节数太少谈不上分段', () {
      expect(morningPeriodCountFromAnchors(<double>[]), 0);
      expect(morningPeriodCountFromAnchors(<double>[100]), 1);
      expect(morningPeriodCountFromAnchors(<double>[100, 170]), 2);
    });
  });

  group('时间文本与分钟数互转', () {
    test('分钟数 → HH:mm', () {
      expect(minutesToLabel(0), '00:00');
      expect(minutesToLabel(8 * 60), '08:00');
      expect(minutesToLabel(11 * 60 + 40), '11:40');
      expect(minutesToLabel(23 * 60 + 59), '23:59');
    });

    test('★ 用户手输的各种写法都认（补零 / 不补零 / 全角冒号 / 无冒号）', () {
      expect(labelToMinutes('08:00'), 480);
      expect(labelToMinutes('8:00'), 480);
      expect(labelToMinutes('8：00'), 480, reason: '中文输入法下很容易打出全角冒号');
      expect(labelToMinutes(' 8:00 '), 480);
      expect(labelToMinutes('0800'), 480);
      expect(labelToMinutes('19:30'), 1170);
    });

    test('认不出来的返回 null，不猜', () {
      expect(labelToMinutes(''), isNull);
      expect(labelToMinutes('abc'), isNull);
      expect(labelToMinutes('25:00'), isNull);
      expect(labelToMinutes('8:70'), isNull);
      expect(labelToMinutes('8'), isNull);
    });

    test('round-trip 稳定', () {
      for (final int m in <int>[0, 1, 480, 700, 840, 1050, 1170, 1439]) {
        expect(labelToMinutes(minutesToLabel(m)), m);
      }
    });
  });

  group('课程配色', () {
    test('★ 同一个课名永远同一个色（周一的数学和周五的数学必须同色）', () {
      final Map<String, int> map = assignColorIndexes(
        <String>['材料力学', '流体力学', '材料力学', '量子光学', '流体力学'],
        8,
      );
      expect(map['材料力学'], isNotNull);
      expect(map['流体力学'], isNotNull);
      expect(map.length, 3, reason: '三个课名只该占三个色号');
    });

    test('不同课名尽量摊开，不挤在同一个色上', () {
      final Map<String, int> map = assignColorIndexes(
        <String>['A', 'B', 'C', 'D'],
        8,
      );
      expect(map.values.toSet().length, 4, reason: '色板够大时四门课该有四个色');
    });

    test('课名比色板多时循环复用，不会越界', () {
      final Map<String, int> map = assignColorIndexes(
        <String>['A', 'B', 'C', 'D', 'E'],
        3,
      );
      expect(map.length, 5);
      for (final int i in map.values) {
        expect(i, inInclusiveRange(0, 2));
      }
    });

    test('空课名被跳过，不占色号', () {
      final Map<String, int> map = assignColorIndexes(
        <String>['  ', '', '语文'],
        4,
      );
      expect(map.length, 1);
      expect(map['语文'], 0);
    });
  });

  group('Course 模型', () {
    test('跨节课程能算出占几个节次', () {
      final Course c = Course(
        id: 1,
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
        name: '材料力学',
        location: '问渠楼 307',
        createdAt: DateTime(2026, 10, 6),
      );
      expect(c.periodSpan, 2);
      expect(c.spansMultiplePeriods, isTrue);
    });

    test('单节课 periodSpan 为 1', () {
      final Course c = Course(
        id: 2,
        weekday: 3,
        startPeriod: 5,
        endPeriod: 5,
        name: '体育',
        createdAt: DateTime(2026, 10, 6),
      );
      expect(c.periodSpan, 1);
      expect(c.spansMultiplePeriods, isFalse);
    });

    test('行映射 round-trip 无损', () {
      final Course c = Course(
        id: 7,
        weekday: 5,
        startPeriod: 3,
        endPeriod: 4,
        name: '量子光学',
        location: '修远楼 A101',
        colorIndex: 2,
        createdAt: DateTime(2026, 10, 6, 22, 30),
      );

      final Course back = CourseMapper.fromRow(CourseMapper.toRow(c));
      expect(back, c);
    });

    test('★ 新增行不含 id（交给 SQLite 自增）', () {
      final Course c = Course(
        id: 99,
        weekday: 1,
        startPeriod: 1,
        endPeriod: 1,
        name: 'x',
        createdAt: DateTime(2026, 10, 6),
      );
      expect(CourseMapper.toInsertRow(c).containsKey('id'), isFalse);
    });

    test('脏数据不抛异常（缺字段 / 时间格式不对）', () {
      final Course c = CourseMapper.fromRow(<String, Object?>{
        'id': 1,
        'weekday': 2,
        'start_period': 1,
        'end_period': 1,
        'name': '语文',
        'created_at': '不是时间',
      });
      expect(c.name, '语文');
      expect(c.location, '');
      expect(c.colorIndex, 0);
    });
  });
}
