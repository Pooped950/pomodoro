/// 统计聚合 —— 全部是**纯函数**，宿主机可直接单测，不用连数据库。
///
/// ## 方案既定：统计不建表，从 `sessions` 实时聚合
///
/// 所以这里没有任何"统计表"，只有把一批 [SessionRecord] 揉成几个数字的纯函数。
/// 好处是：口径改了只改这里一处，历史数据自动按新口径重算，
/// 不会出现"统计表和明细对不上"的经典问题。
///
/// ## 归属日期的口径
///
/// 一律按 `startedAt` 所在的**本地日期**归属，与
/// `SessionRepository.completedFocusCountOn`（主界面「今日 N/8」）保持一致 ——
/// 两处口径不一致的话，主界面说今天 3 个、统计页说 4 个，用户会认为数据是错的。
///
/// 边界情况：23:50 开始、次日 00:15 结束的番茄，算**开始那天**的。
/// 一个番茄只属于一天，不劈成两半 —— 劈开的话"今天完成 1 个番茄"
/// 这种计数就没法定义了。
library;

import 'package:meta/meta.dart';

import '../task/task.dart';
import '../timer/session_record.dart';
import '../timer/timer_state.dart';

// ---------------------------------------------------------------------
// 模型
// ---------------------------------------------------------------------

/// 单日概览
@immutable
class DayOverview {
  const DayOverview({
    required this.focusSeconds,
    required this.breakSeconds,
    required this.completedPomodoros,
    required this.focusSessionCount,
    required this.abandonedCount,
  });

  static const DayOverview empty = DayOverview(
    focusSeconds: 0,
    breakSeconds: 0,
    completedPomodoros: 0,
    focusSessionCount: 0,
    abandonedCount: 0,
  );

  /// 专注总时长（秒）。
  ///
  /// **含未走完的专注**（跳过 / 放弃）—— 因为用户确实在那上面花了时间，
  /// 统计"专注时长"就该如实反映。是否"算一个番茄"是另一回事，
  /// 由 [completedPomodoros] 单独表达。
  final int focusSeconds;

  /// 休息总时长（秒），短休息 + 长休息
  final int breakSeconds;

  /// 完成番茄数（专注 + 完整走完）
  final int completedPomodoros;

  /// 专注记录条数（含未走完的）
  final int focusSessionCount;

  /// 其中没走完就跳过 / 放弃的条数
  final int abandonedCount;

  /// 专注平均单次时长（秒）。没有专注记录时返回 0。
  int get averageFocusSeconds =>
      focusSessionCount == 0 ? 0 : focusSeconds ~/ focusSessionCount;

  /// 完成率：走完的专注 / 全部专注。没有专注记录时按 0 算。
  double get completionRate => focusSessionCount == 0
      ? 0
      : completedPomodoros / focusSessionCount;

  bool get isEmpty =>
      focusSeconds == 0 &&
      breakSeconds == 0 &&
      completedPomodoros == 0 &&
      focusSessionCount == 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DayOverview &&
          other.focusSeconds == focusSeconds &&
          other.breakSeconds == breakSeconds &&
          other.completedPomodoros == completedPomodoros &&
          other.focusSessionCount == focusSessionCount &&
          other.abandonedCount == abandonedCount;

  @override
  int get hashCode => Object.hash(
        focusSeconds,
        breakSeconds,
        completedPomodoros,
        focusSessionCount,
        abandonedCount,
      );

  @override
  String toString() => 'DayOverview(专注 ${focusSeconds}s / 番茄 $completedPomodoros '
      '/ 休息 ${breakSeconds}s)';
}

/// 柱状图的一天
@immutable
class DailyFocus {
  const DailyFocus({
    required this.day,
    required this.focusSeconds,
    required this.completedPomodoros,
  });

  /// 当天 0 点（本地时区）
  final DateTime day;
  final int focusSeconds;
  final int completedPomodoros;

  bool get hasData => focusSeconds > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyFocus &&
          other.day == day &&
          other.focusSeconds == focusSeconds &&
          other.completedPomodoros == completedPomodoros;

  @override
  int get hashCode => Object.hash(day, focusSeconds, completedPomodoros);
}

/// 任务分布里的一片
@immutable
class TaskSlice {
  const TaskSlice({
    required this.taskId,
    required this.label,
    required this.focusSeconds,
    required this.completedPomodoros,
  });

  /// null = 没有绑定任务的那部分
  final int? taskId;

  /// 展示名。任务被删掉时是「已删除的任务」。
  final String label;

  final int focusSeconds;
  final int completedPomodoros;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskSlice &&
          other.taskId == taskId &&
          other.label == label &&
          other.focusSeconds == focusSeconds &&
          other.completedPomodoros == completedPomodoros;

  @override
  int get hashCode =>
      Object.hash(taskId, label, focusSeconds, completedPomodoros);
}

// ---------------------------------------------------------------------
// 聚合
// ---------------------------------------------------------------------

/// 某一天的概览。[day] 传当天任意时刻即可（只取年月日）。
DayOverview summarizeDay(List<SessionRecord> sessions, DateTime day) {
  int focus = 0;
  int rest = 0;
  int completed = 0;
  int focusCount = 0;
  int abandoned = 0;

  for (final SessionRecord r in sessions) {
    if (!isSameDay(r.startedAt, day)) continue;

    if (r.phase == TimerPhase.focus) {
      focus += r.actualSeconds;
      focusCount++;
      if (r.countsAsPomodoro) {
        completed++;
      } else {
        abandoned++;
      }
    } else {
      rest += r.actualSeconds;
    }
  }

  return DayOverview(
    focusSeconds: focus,
    breakSeconds: rest,
    completedPomodoros: completed,
    focusSessionCount: focusCount,
    abandonedCount: abandoned,
  );
}

/// 最近 [days] 天的专注序列，**按时间升序**（最后一根柱子是 [endDay] 那天）。
///
/// 没有记录的那天也会占一根柱子（值为 0）—— 柱状图必须每天都有一根，
/// 缺了的话横轴日期会错位，看起来像"那天不存在"。
List<DailyFocus> dailyFocusSeries(
  List<SessionRecord> sessions, {
  required DateTime endDay,
  int days = 7,
}) {
  final int count = days < 1 ? 1 : days;
  final DateTime last = DateTime(endDay.year, endDay.month, endDay.day);

  final Map<DateTime, ({int seconds, int pomodoros})> byDay =
      <DateTime, ({int seconds, int pomodoros})>{};

  for (final SessionRecord r in sessions) {
    if (r.phase != TimerPhase.focus) continue;
    final DateTime key = DateTime(
      r.startedAt.year,
      r.startedAt.month,
      r.startedAt.day,
    );
    final ({int seconds, int pomodoros}) prev =
        byDay[key] ?? (seconds: 0, pomodoros: 0);
    byDay[key] = (
      seconds: prev.seconds + r.actualSeconds,
      pomodoros: prev.pomodoros + (r.countsAsPomodoro ? 1 : 0),
    );
  }

  final List<DailyFocus> out = <DailyFocus>[];
  for (int i = count - 1; i >= 0; i--) {
    final DateTime day = last.subtract(Duration(days: i));
    final ({int seconds, int pomodoros})? v = byDay[day];
    out.add(
      DailyFocus(
        day: day,
        focusSeconds: v?.seconds ?? 0,
        completedPomodoros: v?.pomodoros ?? 0,
      ),
    );
  }
  return out;
}

/// 专注时间的任务分布，**按时长降序**。
///
/// [tasks] 用来把 taskId 翻译成标题。查不到 id 的任务（已被删除）单独归一类 ——
/// 直接丢掉的话，用户会觉得"我明明专注了，统计里怎么少了一截"。
///
/// [limit] 限制返回条数（把长尾合并成「其他」）。null 表示不限制。
List<TaskSlice> taskDistribution(
  List<SessionRecord> sessions, {
  required List<Task> tasks,
  int? limit,
}) {
  final Map<String, Task> byId = <String, Task>{
    for (final Task t in tasks) '${t.id}': t,
  };

  // key 用字符串，null（未绑定）单独一个桶
  final Map<String, ({int? taskId, int seconds, int pomodoros})> buckets =
      <String, ({int? taskId, int seconds, int pomodoros})>{};

  for (final SessionRecord r in sessions) {
    if (r.phase != TimerPhase.focus) continue;
    final String key = r.taskId?.toString() ?? '__unbound__';
    final ({int? taskId, int seconds, int pomodoros}) prev =
        buckets[key] ?? (taskId: r.taskId, seconds: 0, pomodoros: 0);
    buckets[key] = (
      taskId: r.taskId,
      seconds: prev.seconds + r.actualSeconds,
      pomodoros: prev.pomodoros + (r.countsAsPomodoro ? 1 : 0),
    );
  }

  final List<TaskSlice> slices = <TaskSlice>[
    for (final MapEntry<String, ({int? taskId, int seconds, int pomodoros})> e
        in buckets.entries)
      TaskSlice(
        taskId: e.value.taskId,
        label: _labelFor(e.value.taskId, byId),
        focusSeconds: e.value.seconds,
        completedPomodoros: e.value.pomodoros,
      ),
  ];

  slices.sort((TaskSlice a, TaskSlice b) {
    final int bySeconds = b.focusSeconds.compareTo(a.focusSeconds);
    if (bySeconds != 0) return bySeconds;
    // 时长相同按名字排，保证顺序稳定（否则每次刷新顺序会跳）
    return a.label.compareTo(b.label);
  });

  if (limit == null || slices.length <= limit) return slices;

  final List<TaskSlice> head = slices.sublist(0, limit);
  int restSeconds = 0;
  int restPomodoros = 0;
  for (final TaskSlice s in slices.sublist(limit)) {
    restSeconds += s.focusSeconds;
    restPomodoros += s.completedPomodoros;
  }
  return <TaskSlice>[
    ...head,
    TaskSlice(
      taskId: null,
      label: '其他',
      focusSeconds: restSeconds,
      completedPomodoros: restPomodoros,
    ),
  ];
}

String _labelFor(int? taskId, Map<String, Task> byId) {
  if (taskId == null) return '未绑定任务';
  final Task? t = byId['$taskId'];
  if (t == null) return '已删除的任务';
  return t.title;
}

/// 柱状图的归一化基准：最大单日专注秒数。全为 0 时返回 0（调用方自己兜底）。
int maxFocusSeconds(List<DailyFocus> series) {
  int max = 0;
  for (final DailyFocus d in series) {
    if (d.focusSeconds > max) max = d.focusSeconds;
  }
  return max;
}

/// 同一天（本地时区，只比年月日）
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ---------------------------------------------------------------------
// 日期标签
// ---------------------------------------------------------------------

const List<String> _weekdayChars = <String>['一', '二', '三', '四', '五', '六', '日'];

/// 「周一」这种短标签。柱状图横轴用。
String weekdayShort(DateTime day) {
  final int idx = day.weekday - 1; // weekday: 1=周一 … 7=周日
  if (idx < 0 || idx >= _weekdayChars.length) return '';
  return '周${_weekdayChars[idx]}';
}

/// 「10/5」这种短标签。
String monthDayLabel(DateTime day) => '${day.month}/${day.day}';

/// 今日概览的标题：「今天」/「10月5日」
String dayTitle(DateTime day, DateTime today) =>
    isSameDay(day, today) ? '今天' : '${day.month}月${day.day}日';
