import 'package:meta/meta.dart';

import 'course.dart';
import 'period_time.dart';

/// 一条「上课提醒」—— 星期几、当天第几分钟提醒、提醒哪门课。
///
/// ## 为什么只存「星期 + 分钟数」而不是绝对时间戳
///
/// 课表是**每周重复**的。存绝对时间戳的话，App 一周不打开就全过期了；
/// 存「周一 07:50」这种**规则**，排程方（原生侧）每次响完自己算下一个，
/// 只要课程表没变就永远有效。
///
/// 纯数据，不依赖 Flutter —— 宿主机可直接单测。
@immutable
class ClassReminder {
  const ClassReminder({
    required this.weekday,
    required this.minuteOfDay,
    required this.title,
    required this.body,
  });

  /// 1 = 周一 … 7 = 周日（和 [Course.weekday] 同一套）
  final int weekday;

  /// 当天第几分钟（0~1439）—— 提醒触发的时刻
  final int minuteOfDay;

  /// 通知标题（课名）
  final String title;

  /// 通知正文（`08:00 上课 · 教2-213`）
  final String body;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassReminder &&
          other.weekday == weekday &&
          other.minuteOfDay == minuteOfDay &&
          other.title == title &&
          other.body == body;

  @override
  int get hashCode => Object.hash(weekday, minuteOfDay, title, body);

  @override
  String toString() =>
      '周$weekday ${minutesToLabel(minuteOfDay)} $title（$body）';
}

/// 默认提前量：上课前 **10 分钟**（用户 2026-10-09 要求）。
const int kDefaultLeadMinutes = 10;

/// 从「课程表 + 节次时间表」算出所有上课提醒。**纯函数。**
///
/// ## 规则
///
///   - 提醒时刻 = 该课**第一节**的开始时间 − [leadMinutes]
///   - 跨节连排的课（3-4 节）只在**第 3 节**开始前提醒一次，不重复打扰
///   - 节次时间表里查不到的节次（用户改过课表 / 数据不一致）直接跳过 ——
///     宁可漏一条，也不要瞎猜一个时间
///   - 算出来是负数的（第一节 00:05 之类）跳过
///   - 同一天、同一时刻、同一课名去重（同一门课被拆成两条记录时会撞）
///
/// 返回结果按「星期 → 时刻」升序，方便人看、也方便测试断言。
List<ClassReminder> buildClassReminders({
  required List<Course> courses,
  required TimetableSchedule schedule,
  int leadMinutes = kDefaultLeadMinutes,
}) {
  final List<ClassReminder> out = <ClassReminder>[];

  for (final Course c in courses) {
    final PeriodTime? p = schedule.forPeriod(c.startPeriod);
    if (p == null) continue;

    final int at = p.startMinute - leadMinutes;
    if (at < 0 || at >= 1440) continue;

    final String name = c.name.trim();
    if (name.isEmpty) continue;

    final String loc = c.location.trim();
    out.add(ClassReminder(
      weekday: c.weekday,
      minuteOfDay: at,
      title: name,
      body: loc.isEmpty
          ? '${minutesToLabel(p.startMinute)} 上课'
          : '${minutesToLabel(p.startMinute)} 上课 · $loc',
    ));
  }

  // 去重：同一「星期 + 时刻 + 课名」只留一条
  final Map<String, ClassReminder> uniq = <String, ClassReminder>{};
  for (final ClassReminder r in out) {
    uniq.putIfAbsent('${r.weekday}|${r.minuteOfDay}|${r.title}', () => r);
  }

  final List<ClassReminder> result = uniq.values.toList()
    ..sort((ClassReminder a, ClassReminder b) {
      final int byDay = a.weekday.compareTo(b.weekday);
      if (byDay != 0) return byDay;
      return a.minuteOfDay.compareTo(b.minuteOfDay);
    });
  return result;
}
