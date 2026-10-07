import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/motion_tokens.dart';
import '../../providers/stats_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/app_segmented_tabs.dart';
import '../../widgets/motion_scope.dart';
import '../stats/stats_view.dart';
import '../tasks/tasks_view.dart';

/// 第二页 —— 「任务」与「统计」合并成一页，顶部两个小标签切换。
///
/// ## 为什么合并（2026-10-06 用户提的）
///
/// 统计是"看"的，任务是要动手的，但两者回答的是同一个问题：
/// 「我的专注时间花到哪去了」。各占一个底部标签太奢侈 ——
/// 腾出来的那一格给了课表页。
///
/// ## 布局
///
/// ```
/// [任务][统计]                   ← AppSegmentedTabs（左）
///                         [+]    ← 当前标签对应的操作（右）
/// ──────────────────────────
/// 当前标签的内容（IndexedStack）
/// ```
///
/// ## 为什么用 IndexedStack
///
/// 和 `AppShell` 用 `PageView` + `_KeepAlivePage` 保活是同一个道理：
/// 切回来不该丢滚动位置、也不该重新取数。`IndexedStack` 一次性构建两边、
/// 只显示一个，天然保活。
class TaskStatsPage extends ConsumerStatefulWidget {
  const TaskStatsPage({super.key});

  @override
  ConsumerState<TaskStatsPage> createState() => _TaskStatsPageState();
}

class _TaskStatsPageState extends ConsumerState<TaskStatsPage> {
  static const int _tabTasks = 0;
  static const int _tabStats = 1;

  int _tab = _tabTasks;

  void _switchTo(int next) {
    if (next == _tab) return;
    setState(() => _tab = next);
    _refresh(next);
  }

  /// 切标签时让对应数据源失效。
  ///
  /// 两个视图都被 `IndexedStack` 保活着，不会自己重建、也就不会重新取数 ——
  /// 不主动刷的话，"刚跑完一个番茄 → 切到统计"看到的还是旧数字。
  /// 这和 `AppShell._refreshFor` 处理底部切页是同一个道理。
  void _refresh(int tab) {
    if (tab == _tabStats) {
      ref.invalidate(statsProvider);
    } else {
      unawaited(ref.read(taskListProvider.notifier).refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final Motion motion = MotionScope.of(context);

    return SafeArea(
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.tight,
              AppSpacing.page,
              0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
                child: Row(
                  children: <Widget>[
                    AppSegmentedTabs(
                      labels: const <String>['任务', '统计'],
                      index: _tab,
                      onChanged: _switchTo,
                    ),
                    const Spacer(),

                    // 操作按钮跟着标签换：任务 = 新建，统计 = 刷新。
                    // 用 AnimatedSwitcher 淡入淡出 + 轻微缩放，避免"啪"地换个图标
                    AnimatedSwitcher(
                      duration: motion.standard,
                      switchInCurve: MotionTokens.emphasized,
                      switchOutCurve: MotionTokens.soft,
                      transitionBuilder: (Widget child, Animation<double> a) {
                        return FadeTransition(
                          opacity: a,
                          child: ScaleTransition(
                            scale:
                                Tween<double>(begin: 0.86, end: 1).animate(a),
                            child: child,
                          ),
                        );
                      },
                      child: _tab == _tabTasks
                          ? IconButton(
                              key: const ValueKey<String>('task-add'),
                              onPressed: () => showTaskEditor(
                                context,
                                ref.read(taskListProvider.notifier),
                              ),
                              icon: const Icon(Icons.add_rounded),
                              tooltip: '新建任务',
                            )
                          : IconButton(
                              key: const ValueKey<String>('stats-refresh'),
                              onPressed: () => ref.invalidate(statsProvider),
                              icon: const Icon(Icons.refresh_rounded),
                              tooltip: '刷新',
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const <Widget>[
                TasksView(),
                StatsView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
