import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/settings/class_reminder_settings.dart';
import 'package:pomodoro/domain/timetable/class_reminder.dart';
import 'package:pomodoro/domain/timetable/course.dart';
import 'package:pomodoro/domain/timetable/period_time.dart';

/// 上课提醒的**规则计算**（纯函数）。
///
/// 这是「每节课上课前 10 分钟提醒」这条需求的落点：Dart 只算规则，
/// 排闹钟 / 发通知在原生侧（`ClassReminderScheduler` + `ClassAlarmReceiver`）。
/// 所以这里把"算什么"钉死，原生那半边只负责"按时响"。
Course c(
  int weekday,
  int startPeriod,
  int endPeriod,
  String name, {
  String location = '',
  int id = 0,
}) =>
    Course(
      id: id,
      weekday: weekday,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      name: name,
      location: location,
      createdAt: DateTime(2026, 10, 9),
    );

/// 一张简单的节次表：第 1 节 08:00、第 2 节 09:00、第 3 节 10:00、第 4 节 11:00
const TimetableSchedule sched = TimetableSchedule(
  periods: <PeriodTime>[
    PeriodTime(period: 1, startMinute: 480, endMinute: 525),
    PeriodTime(period: 2, startMinute: 540, endMinute: 585),
    PeriodTime(period: 3, startMinute: 600, endMinute: 645),
    PeriodTime(period: 4, startMinute: 660, endMinute: 705),
  ],
);

void main() {
  mainSettings();

  group('buildClassReminders', () {
    test('★ 提醒时刻 = 上课时间 − 10 分钟', () {
      final List<ClassReminder> rs = buildClassReminders(
        courses: <Course>[c(1, 1, 2, '排球初级', location: '排球场')],
        schedule: sched,
      );
      expect(rs.length, 1);
      expect(rs[0].weekday, 1);
      expect(rs[0].minuteOfDay, 470); // 08:00 − 10min = 07:50
      expect(minutesToLabel(rs[0].minuteOfDay), '07:50');
      expect(rs[0].title, '排球初级');
      expect(rs[0].body, '08:00 上课 · 排球场');
    });

    test('★ 跨节连排的课只在第一节前提醒一次', () {
      final List<ClassReminder> rs = buildClassReminders(
        courses: <Course>[c(1, 1, 4, '高数', location: '教101')],
        schedule: sched,
      );
      expect(rs.length, 1, reason: '第 1-4 节是一门课，不该提醒 4 次');
      expect(rs[0].minuteOfDay, 470);
    });

    test('同一门课不同天各提醒一次', () {
      final List<ClassReminder> rs = buildClassReminders(
        courses: <Course>[
          c(1, 1, 2, '高数', id: 1),
          c(3, 1, 2, '高数', id: 2),
        ],
        schedule: sched,
      );
      expect(rs.length, 2);
      expect(rs.map((ClassReminder r) => r.weekday).toList(), <int>[1, 3]);
    });

    test('没有教室时正文不带「·」', () {
      final List<ClassReminder> rs = buildClassReminders(
        courses: <Course>[c(2, 2, 2, '英语')],
        schedule: sched,
      );
      expect(rs[0].body, '09:00 上课');
    });

    test('节次时间表里查不到的节次 → 跳过（宁可不提醒，也不瞎猜时间）', () {
      final List<ClassReminder> rs = buildClassReminders(
        courses: <Course>[
          c(1, 9, 9, '不存在的第九节'),
          c(2, 1, 1, '正常的课'),
        ],
        schedule: sched,
      );
      expect(rs.length, 1);
      expect(rs[0].title, '正常的课');
    });

    test('课名为空 → 跳过', () {
      final List<ClassReminder> rs = buildClassReminders(
        courses: <Course>[c(1, 1, 1, '   ')],
        schedule: sched,
      );
      expect(rs, isEmpty);
    });

    test('提前量算出来是负数 → 跳过（不会跨到前一天去）', () {
      const TimetableSchedule early = TimetableSchedule(
        periods: <PeriodTime>[
          PeriodTime(period: 1, startMinute: 5, endMinute: 45), // 00:05 上课
        ],
      );
      final List<ClassReminder> rs = buildClassReminders(
        courses: <Course>[c(1, 1, 1, '凌晨的课')],
        schedule: early,
      );
      expect(rs, isEmpty);
    });

    test('同一「星期 + 时刻 + 课名」去重', () {
      final List<ClassReminder> rs = buildClassReminders(
        courses: <Course>[
          c(1, 1, 2, '高数', id: 1),
          c(1, 1, 2, '高数', id: 2), // 重复记录（同一格被插了两次）
        ],
        schedule: sched,
      );
      expect(rs.length, 1);
    });

    test('结果按「星期 → 时刻」升序', () {
      final List<ClassReminder> rs = buildClassReminders(
        courses: <Course>[
          c(5, 3, 4, '周五下午'),
          c(1, 3, 4, '周一下午'),
          c(1, 1, 2, '周一上午'),
        ],
        schedule: sched,
      );
      expect(
        rs.map((ClassReminder r) => '${r.weekday}@${r.minuteOfDay}').toList(),
        <String>['1@470', '1@590', '5@590'],
      );
    });

    test('提前量可以改（默认 10 分钟）', () {
      expect(kDefaultLeadMinutes, 10);
      final List<ClassReminder> rs = buildClassReminders(
        courses: <Course>[c(1, 1, 1, '高数')],
        schedule: sched,
        leadMinutes: 20,
      );
      expect(rs[0].minuteOfDay, 460); // 07:40
    });

    test('空课表 → 没有提醒', () {
      expect(
        buildClassReminders(courses: const <Course>[], schedule: sched),
        isEmpty,
      );
    });
  });
}

// ===========================================================================
// 提醒方式（震动 / 响铃 两个复选框）
// ===========================================================================

void mainSettings() {
  group('ClassReminderSettings', () {
    test('★ 四种组合 → 三个渠道 / 不提醒', () {
      // 默认：两个都开
      const ClassReminderSettings d = ClassReminderSettings();
      expect(d.vibrate, isTrue);
      expect(d.sound, isTrue);
      expect(d.enabled, isTrue);
      expect(d.channel, 'pomodoro_class');

      // 只震动
      final ClassReminderSettings vibOnly = d.copyWith(sound: false);
      expect(vibOnly.enabled, isTrue);
      expect(vibOnly.channel, 'pomodoro_class_vibrate');

      // 只响铃
      final ClassReminderSettings soundOnly = d.copyWith(vibrate: false);
      expect(soundOnly.enabled, isTrue);
      expect(soundOnly.channel, 'pomodoro_class_sound');

      // 两个都关 = 不提醒
      final ClassReminderSettings off =
          d.copyWith(vibrate: false, sound: false);
      expect(off.enabled, isFalse, reason: '两个都关必须等于「不提醒」');
    });

    test('JSON 往返', () {
      final ClassReminderSettings s =
          const ClassReminderSettings(vibrate: false, sound: true);
      final ClassReminderSettings back =
          ClassReminderSettings.fromJson(s.toJson());
      expect(back, s);
    });

    test('脏数据回退默认值（两个都开）', () {
      expect(ClassReminderSettings.fromJson(<String, Object?>{}),
          const ClassReminderSettings());
      expect(
        ClassReminderSettings.fromJson(<String, Object?>{
          'vibrate': 'yes',
          'sound': 1,
        }),
        const ClassReminderSettings(),
      );
      // 只给一个字段 → 另一个用默认
      expect(
        ClassReminderSettings.fromJson(<String, Object?>{'sound': false}),
        const ClassReminderSettings(sound: false),
      );
    });
  });
}
