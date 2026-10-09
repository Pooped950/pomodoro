import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/task/task.dart';
import '../../../domain/timer/timer_state.dart';
import '../../providers/task_provider.dart';
import '../../providers/timer_provider.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/motion_scope.dart';
import '../../widgets/pressable.dart';
import 'widgets/control_buttons.dart';
import 'widgets/timer_ring.dart';

/// 每日目标番茄数（P0 先写死，后续移到设置页）
const int kDailyGoal = 8;

/// 主界面 / 计时页
class HomePage extends ConsumerWidget {
  const HomePage({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ⚠️ **不要在这里 watch `nowProvider`**（2026-10-09 性能优化）。
    //
    // 它每秒变一次，在这层 watch 会把整页 —— 头部进度、任务条、环形、
    // 控制按钮 —— 全部重建一遍。低端机上就是肉眼可见的掉帧。
    // 真正依赖"现在几点"的只有环形里的倒计时文字和进度弧，
    // 所以那部分单独抽成了 [_LiveTimerRing]。
    final TimerState state = ref.watch(timerProvider);
    // M4：今日完成数从 sessions 实时聚合（不再用内存里的轮次计数）
    final int todayCount = ref.watch(todayFocusCountProvider).value ?? 0;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final Color accent = _accentFor(state.phase, scheme);
    final Motion motion = MotionScope.of(context);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: Column(
              children: <Widget>[
                const SizedBox(height: AppSpacing.tight),

                // 顶部：今日进度 + 设置入口
                AnimatedOpacity(
                  duration: motion.standard,
                  curve: Curves.easeOut,
                  // 计时进行中降低视觉权重，减少干扰
                  opacity: state.isRunning ? 0.45 : 1.0,
                  child: _HeaderRow(
                    completed: todayCount,
                    goal: kDailyGoal,
                    onOpenSettings: onOpenSettings,
                  ),
                ),

                // 任务绑定（M5-②）：开始专注时会把这里选的任务记进本次专注。
                // 计时中同样降权 —— 它只影响"下一次开始"，跑着的时候不该抢注意力。
                const SizedBox(height: AppSpacing.tight),
                AnimatedOpacity(
                  duration: motion.standard,
                  curve: Curves.easeOut,
                  opacity: state.isRunning ? 0.45 : 1.0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _TaskBindingChip(
                      task: ref.watch(selectedTaskProvider),
                      onTap: () => _pickTask(context, ref),
                    ),
                  ),
                ),

                // 环形进度（自适应剩余空间）
                Expanded(
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints c) {
                      final double ringSize = math.min(
                        c.maxWidth * kRingWidthRatio,
                        c.maxHeight * 0.94,
                      );
                      return Center(
                        child: _LiveTimerRing(
                          state: state,
                          color: accent,
                          size: ringSize,
                        ),
                      );
                    },
                  ),
                ),

                ControlButtons(
                  phase: state.phase,
                  isIdle: state.isIdle,
                  isRunning: state.isRunning,
                  accentColor: accent,
                  onToggle: () => ref.read(timerProvider.notifier).toggle(),
                  onSkip: () => ref.read(timerProvider.notifier).skip(),
                  onAbandon: () => ref.read(timerProvider.notifier).abandon(),
                ),

                // 给底部悬浮导航条留出空间（Scaffold 开了 extendBody）
                const SizedBox(height: kBottomNavSpace),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 专注用主色（暖），休息用第三色（冷）。
/// 这是符合直觉的语义映射 —— 方案 5.2 节配色约定。
Color _accentFor(TimerPhase phase, ColorScheme scheme) => switch (phase) {
      TimerPhase.focus => scheme.primary,
      TimerPhase.shortBreak => scheme.tertiary,
      TimerPhase.longBreak => scheme.secondary,
    };

/// **全页唯一跟着秒针重建的地方**（2026-10-09 性能优化）。
///
/// ## 为什么单独拆出来
///
/// 倒计时文字和进度弧每秒都要变，但页面上的其它东西 —— 头部进度、
/// 任务绑定条、三个控制按钮、底部留白 —— **一年也不变一次**。
/// 之前在 `HomePage.build` 里 `ref.watch(nowProvider)`，等于让整页
/// 每秒重建：低端机上每一秒都要重新布局一整棵子树，肉眼可见地卡。
///
/// 拆出来之后，每秒重建的只有这一个 `TimerRing`。
///
/// ⚠️ 外面再套一层 [RepaintBoundary]：环形是 `CustomPaint` 画的，
/// 每秒重绘一次，用边界把它和页面上其它绘制隔开，
/// 免得一次重绘把整屏都拖进重绘区（低端机 GPU 填充率本来就紧张）。
class _LiveTimerRing extends ConsumerWidget {
  const _LiveTimerRing({
    required this.state,
    required this.color,
    required this.size,
  });

  final TimerState state;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DateTime now = ref.watch(nowProvider);
    return RepaintBoundary(
      child: TimerRing(
        fraction: state.remainingFractionAt(now),
        timeText: formatClock(state.remainingSecondsAt(now)),
        phaseLabel: state.isIdle
            ? state.phase.idleLabel
            : (state.isPaused ? '已暂停' : state.phase.label),
        color: color,
        size: size,
        animate: !state.isIdle,
      ),
    );
  }
}

/// 弹出任务选择器，把结果写进 [selectedTaskIdProvider]。
///
/// 用 `-1` 当"不绑定"的哨兵值 —— 因为弹层被划走时返回的也是 null，
/// 不区分的话没法判断用户是"取消"还是"选了不绑定"。
Future<void> _pickTask(BuildContext context, WidgetRef ref) async {
  final int? picked = await showAppSheet<int>(
    context: context,
    // 不在这里取任务列表：让弹层自己 watch，这样"任务还没加载完就打开"
    // 也能在加载完成后自动刷新出来（否则会看到一次空列表）
    builder: (BuildContext _) => const _TaskPickerSheet(),
  );
  if (picked == null) return; // 划走 / 点外部 = 取消，不改绑定
  ref.read(selectedTaskIdProvider.notifier).select(picked == -1 ? null : picked);
}

/// 计时页顶部的任务绑定小胶囊
class _TaskBindingChip extends StatelessWidget {
  const _TaskBindingChip({required this.task, required this.onTap});

  final Task? task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final bool bound = task != null;

    final Color color = bound
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: 0.5);

    return Pressable(
      onTap: onTap,
      // 小胶囊可以带一点缩放（整行宽的列表项就不适合，见 Pressable 注释）
      scale: 0.97,
      highlightColor: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        decoration: BoxDecoration(
          color: bound
              ? scheme.primary.withValues(alpha: 0.12)
              : scheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                bound ? Icons.link_rounded : Icons.link_off_rounded,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: Text(
                  bound ? task!.title : '绑定任务',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 任务选择底部弹层。
///
/// **自己 watch 任务列表**，而不是由调用方把列表传进来 ——
/// 否则"任务还没加载完就打开"会看到一次空列表，加载完成后也不会刷新。
class _TaskPickerSheet extends ConsumerWidget {
  const _TaskPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<Task> tasks = ref
        .watch(sortedTasksProvider)
        .where((Task t) => !t.isDone)
        .toList(growable: false);

    return AppSheetScaffold(
      title: '把这次专注绑定到',
      subtitle: '绑定后这次专注会记在这个任务头上',
      children: <Widget>[
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.item,
              0,
              AppSpacing.item,
              AppSpacing.tight,
            ),
            child: Text(
              '还没有进行中的任务 —— 先去「任务」页建一个',
              style: text.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
                height: 1.5,
              ),
            ),
          )
        else
          // Flexible + shrinkWrap：任务多到超出屏幕时列表内部滚动，
          // 而不是把弹层撑到天上去
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: <Widget>[
                for (int i = 0; i < tasks.length; i++)
                  FadeSlideIn(
                    index: i,
                    offsetY: 12,
                    child: SheetActionTile(
                      icon: Icons.check_circle_outline,
                      label: tasks[i].title,
                      subtitle:
                          '${tasks[i].completedPomodoros} / ${tasks[i].estimatedPomodoros} 个番茄',
                      onTap: () => Navigator.of(context).pop(tasks[i].id),
                    ),
                  ),
              ],
            ),
          ),
        FadeSlideIn(
          // 「不绑定」排在所有任务之后，错开延迟也接在它们后面
          index: tasks.isEmpty ? 0 : tasks.length,
          offsetY: 12,
          child: SheetActionTile(
            icon: Icons.link_off_rounded,
            label: '不绑定任务',
            onTap: () => Navigator.of(context).pop(-1),
          ),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.completed,
    required this.goal,
    this.onOpenSettings,
  });

  final int completed;
  final int goal;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final bool reached = completed >= goal;

    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: elevatedSurface(scheme, 0.06),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.local_fire_department_rounded,
                size: 16,
                color: reached ? scheme.primary : scheme.onSurface.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 6),
              Text(
                '今日 $completed / $goal',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
          tooltip: '设置',
        ),
      ],
    );
  }
}
