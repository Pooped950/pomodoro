import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/session_repository.dart';
import '../../domain/stats/stats_summary.dart';
import '../../domain/task/task.dart';
import '../../domain/timer/session_record.dart';
import 'task_provider.dart';

/// 统计页一次要用到的全部数据。
///
/// 三块数据来自**同一批 session 记录**，所以打包在一起返回 ——
/// 分开成三个 provider 的话会各查一次库，不仅多两次往返，
/// 还可能取到不同时刻的快照，出现"柱状图和今日概览对不上"。
class StatsData {
  const StatsData({
    required this.today,
    required this.week,
    required this.tasks,
    required this.weekTotalSeconds,
  });

  static const StatsData empty = StatsData(
    today: DayOverview.empty,
    week: <DailyFocus>[],
    tasks: <TaskSlice>[],
    weekTotalSeconds: 0,
  );

  /// 今日概览
  final DayOverview today;

  /// 最近 7 天专注序列（升序，最后一根是今天）
  final List<DailyFocus> week;

  /// 近 7 天任务分布（按时长降序，长尾合并为「其他」）
  final List<TaskSlice> tasks;

  /// 近 7 天专注合计（秒）
  final int weekTotalSeconds;

  bool get isEmpty => today.isEmpty && weekTotalSeconds == 0;
}

/// 统计页的 7 天窗口长度。做成常量是为了页面上的文案能跟着它走，
/// 不会出现"改了窗口但标题还写着 7 天"。
const int kStatsWindowDays = 7;

/// 统计聚合。窗口 = 最近 [kStatsWindowDays] 天（含今天）。
///
/// 为什么窗口是 7 天而不是"全部历史"：sessions 会随使用无限增长，
/// 每次进统计页全表扫会越来越慢。7 天既能回答"我最近怎么样"，
/// 查询量又恒定。以后要做"全部时间"就再加一个窗口，而不是把这里改大。
final statsProvider = FutureProvider<StatsData>((Ref ref) async {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime from = today.subtract(const Duration(days: kStatsWindowDays - 1));
  // 右开区间要包含"今天一整天"，所以上界是明天 0 点
  final DateTime to = today.add(const Duration(days: 1));

  try {
    final List<SessionRecord> sessions =
        await ref.watch(sessionRepositoryProvider).inRange(from, to);

    // 任务列表用于把 taskId 翻译成标题。**必须无条件 watch** ——
    // 写成条件分支里 watch 的话，依赖集合不稳定（这个坑 M5-② 踩过一次）。
    final List<Task> tasks = ref.watch(taskListProvider);

    final List<DailyFocus> week =
        dailyFocusSeries(sessions, endDay: now, days: kStatsWindowDays);

    int weekTotal = 0;
    for (final DailyFocus d in week) {
      weekTotal += d.focusSeconds;
    }

    return StatsData(
      today: summarizeDay(sessions, now),
      week: week,
      tasks: taskDistribution(sessions, tasks: tasks, limit: 5),
      weekTotalSeconds: weekTotal,
    );
  } catch (_) {
    // 仓库未注入（测试环境）/ 查询失败 → 返回空数据，页面照常渲染空状态
    return StatsData.empty;
  }
});
