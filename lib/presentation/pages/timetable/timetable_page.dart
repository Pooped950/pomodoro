import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/timetable_palette.dart';
import '../../../data/repositories/timetable_repository.dart';
import '../../../domain/remote/remote_config.dart';
import '../../../domain/timetable/course.dart';
import '../../../domain/timetable/course_override.dart';
import '../../providers/timetable_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_context_menu.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/course_edit_dialog.dart';
import '../../widgets/glass_primary_button.dart';
import '../../widgets/pressable.dart';
import '../settings/import_timetable_page.dart';
import 'week_grid_view.dart';

/// 课表页 —— 底部导航第三格（2026-10-06 新增）。
///
/// ## 两个状态
///
/// 1. **还没导入** → 空白态：一句说明 + 一个导入入口。
///    刻意不画空网格占位 —— 一张全是格子的空表反而让人以为"课表是空的"
/// 2. **已经导入** → 周视图网格（[WeekGridView]）+ 一行概要 + 重新导入入口
///
/// ## 每格能做什么（2026-10-10 更新）
///
/// 点每格右上角的三个点：
///
///   - **编辑这节课** —— 改课名 / 教室，**也能挪位置**（换星期、改起止节次）。
///     导入之后发现哪格认错了、或者课换了时间，都走这里，不用重新导入
///   - 本周隐藏（下周自动回来）
///   - 照这格再加一节
///   - 永久删除
///
/// 空白格是「在这里加一节课」。
class TimetablePage extends ConsumerWidget {
  const TimetablePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TimetableSnapshot> async =
        ref.watch(timetableProvider);
    final TextTheme text = Theme.of(context).textTheme;

    final TimetableSnapshot? loaded = async.value;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
          child: ListView(
            // 底部给悬浮导航条留空间
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.tight,
              AppSpacing.page,
              kBottomNavSpace,
            ),
            children: <Widget>[
              Text('课表', style: text.titleLarge),
              const SizedBox(height: AppSpacing.tight),

              if (loaded == null)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.section),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (loaded.isEmpty)
                const _EmptyState()
              else
                _ImportedView(snapshot: loaded),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(
              Icons.calendar_month_outlined,
              color: scheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(height: AppSpacing.item),
          Text('还没有课表', style: text.titleMedium),
          const SizedBox(height: AppSpacing.tight),
          Text(
            '截图两张课表（上下两半，中间留一点重叠），'
            'App 会拼成一张完整的课表再识别，'
            '最后变成一张可以随时改的周视图。',
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.6),
              height: 1.6,
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          GlassPrimaryButton(
            label: t('导入课表'),
            icon: Icons.add_photo_alternate_outlined,
            accent: scheme.primary,
            onPressed: () => _openImport(context),
          ),
        ],
      ),
    );
  }
}

class _ImportedView extends ConsumerWidget {
  const _ImportedView({required this.snapshot});

  final TimetableSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    // 「本周实际显示什么」在视图层算：骨架课表 + 本周生效的例外。
    // 快照带的是原始数据，周一是"今天"的属性，不该进 provider。
    final DateTime monday = mondayOf(DateTime.now());
    final List<Course> effective = effectiveCoursesForWeek(
      courses: snapshot.courses,
      overrides: snapshot.overrides,
      weekMonday: monday,
    );
    final int hiddenCount = snapshot.overrides
        .where(
          (CourseOverride o) =>
              o.kind == CourseOverrideKind.hide &&
              _sameWeek(o.weekMonday, monday),
        )
        .length;

    final int courseCount = effective.length;
    final int periodCount = snapshot.schedule.periods.length;
    final bool hasEvening = snapshot.schedule.evening != null;
    final List<int> days = TimetableSnapshot(
      courses: effective,
      schedule: snapshot.schedule,
    ).activeWeekdays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 一行概要 —— 不占地方，主要是给"网格里到底画了多少东西"一个交代。
        // 详细的核对交给网格本身，所以这里只留最关键的三个数。
        Row(
          children: <Widget>[
            Icon(
              Icons.check_circle_rounded,
              size: 16,
              color: scheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$courseCount 节课 · $periodCount 个节次'
                '${hasEvening ? ' · 有晚自习' : ''}',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.tight),

        if (hiddenCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.tight),
            child: _HiddenBanner(
              count: hiddenCount,
              onRestore: () => _restoreHidden(context, ref, monday),
            ),
          ),
        WeekGridView(
          courses: effective,
          schedule: snapshot.schedule,
          onCellMenu: (Course course, Rect anchor) =>
              _showCellMenu(context, ref, course, anchor, monday),
          onEmptyCellMenu: (int weekday, int period, Rect anchor) =>
              _showAddMenu(context, ref, weekday, period, anchor, monday),
        ),

        const SizedBox(height: AppSpacing.tight),
        Text(
          '上课的日子：${days.map(_weekdayLabel).join(' ')}',
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.45),
          ),
        ),

        const SizedBox(height: AppSpacing.item),
        GlassPrimaryButton(
          label: t('重新导入'),
          icon: Icons.refresh_rounded,
          accent: scheme.primary,
          onPressed: () => _openImport(context),
        ),
      ],
    );
  }
}

// ====================================================================
// 三点点菜单与动作
// ====================================================================

bool _sameWeek(DateTime? a, DateTime b) =>
    a != null && a.year == b.year && a.month == b.month && a.day == b.day;

/// 有课格子的菜单：本周隐藏 / 加课 / 永久删除（临时课是"取消本周加课"）
Future<void> _showCellMenu(
  BuildContext context,
  WidgetRef ref,
  Course course,
  Rect anchor,
  DateTime monday,
) async {
  final bool isTemp = course.id < 0; // 临时课的 id = -overrideId
  final String? choice = await showAppContextMenu<String>(
    context: context,
    anchor: anchor,
    items: <AppContextMenuItem<String>>[
      if (isTemp)
        const AppContextMenuItem<String>(
          value: 'unadd',
          label: '取消本周加课',
          icon: Icons.undo_rounded,
        )
      else ...<AppContextMenuItem<String>>[
        // 改内容和**挪位置**（换星期、改起止节次）是同一个动作 ——
        // 都走这个对话框，用户不用去别处找
        const AppContextMenuItem<String>(
          value: 'edit',
          label: '编辑这节课',
          icon: Icons.edit_outlined,
        ),
        const AppContextMenuItem<String>(
          value: 'hide',
          label: '本周隐藏（下周自动回来）',
          icon: Icons.visibility_off_outlined,
        ),
        const AppContextMenuItem<String>(
          value: 'add',
          label: '照这格再加一节',
          icon: Icons.add_rounded,
        ),
        const AppContextMenuItem<String>(
          value: 'delete',
          label: '永久删除',
          icon: Icons.delete_outline_rounded,
        ),
      ],
    ],
  );
  if (choice == null || !context.mounted) return;
  final TimetableRepository repo = ref.read(timetableRepositoryProvider);

  switch (choice) {
    case 'edit':
      if (!context.mounted) return;
      await _editCourseFlow(context, ref, course, monday);
    case 'hide':
      await repo.insertOverride(
        CourseOverride(
          id: 0,
          kind: CourseOverrideKind.hide,
          weekday: course.weekday,
          startPeriod: course.startPeriod,
          endPeriod: course.endPeriod,
          weekMonday: monday,
          createdAt: DateTime.now(),
        ),
      );
      ref.invalidate(timetableProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('本周已隐藏，下周自动回来')),
        );
      }
    case 'unadd':
      await repo.deleteOverride(-course.id);
      ref.invalidate(timetableProvider);
    case 'add':
      if (!context.mounted) return;
      await _addCourseFlow(
        context,
        ref,
        monday,
        weekday: course.weekday,
        startPeriod: course.startPeriod,
        endPeriod: course.endPeriod,
      );
    case 'delete':
      final bool? ok = await showAppDialog<bool>(
        context: context,
        builder: (BuildContext _) => AlertDialog(
          title: const Text('永久删除？'),
          content: Text(
            '「${course.name}」会从每一周里消失'
            '${course.location.trim().isEmpty ? '' : '（${course.location.trim()}）'}。'
            '如果只是这周不上，建议用「本周隐藏」。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await repo.deleteCourse(course.id);
        ref.invalidate(timetableProvider);
      }
  }
}

/// 编辑一门课：改课名 / 教室 / 星期 / 节次。
///
/// ## 「调整位置」也走这里（2026-10-10 用户要求）
///
/// 用户原话：「单节课没办法调整位置和内容」。其实换星期、改起止节次
/// 和改课名是**同一张表单的字段** —— 没必要单开一个"拖动/移动"交互
/// （拖拽在密集网格里又难对准又容易误触），一个对话框全解决。
Future<void> _editCourseFlow(
  BuildContext context,
  WidgetRef ref,
  Course course,
  DateTime monday,
) async {
  final CourseDraft? draft = await showCourseEditDialog(
    context,
    title: '编辑这节课',
    name: course.name,
    location: course.location,
    weekday: course.weekday,
    startPeriod: course.startPeriod,
    endPeriod: course.endPeriod,
  );
  if (draft == null || !context.mounted) return;

  final TimetableRepository repo = ref.read(timetableRepositoryProvider);

  if (course.id < 0) {
    // 临时课（本周加的那种）在 courses 表里没有行，改不了 ——
    // 只能把旧的取消掉、按新字段重新加一条本周的
    await repo.deleteOverride(-course.id);
    await repo.insertOverride(
      CourseOverride(
        id: 0,
        kind: CourseOverrideKind.add,
        weekday: draft.weekday,
        startPeriod: draft.startPeriod,
        endPeriod: draft.endPeriod,
        weekMonday: monday,
        name: draft.name,
        location: draft.location,
        createdAt: DateTime.now(),
      ),
    );
  } else {
    await repo.updateCourse(
      course.copyWith(
        weekday: draft.weekday,
        startPeriod: draft.startPeriod,
        endPeriod: draft.endPeriod,
        name: draft.name,
        location: draft.location,
      ),
    );
  }

  ref.invalidate(timetableProvider);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存')),
    );
  }
}

/// 空白格的菜单：目前只有加课一个动作
Future<void> _showAddMenu(
  BuildContext context,
  WidgetRef ref,
  int weekday,
  int period,
  Rect anchor,
  DateTime monday,
) async {
  final String? choice = await showAppContextMenu<String>(
    context: context,
    anchor: anchor,
    items: const <AppContextMenuItem<String>>[
      AppContextMenuItem<String>(
        value: 'add',
        label: '在这里加一节课',
        icon: Icons.add_rounded,
      ),
    ],
  );
  if (choice != 'add' || !context.mounted) return;
  await _addCourseFlow(
    context,
    ref,
    monday,
    weekday: weekday,
    startPeriod: period,
    endPeriod: period,
  );
}

/// 加课：先填字段，再选「临时加（本周）」还是「永久加（每周）」
Future<void> _addCourseFlow(
  BuildContext context,
  WidgetRef ref,
  DateTime monday, {
  required int weekday,
  required int startPeriod,
  required int endPeriod,
}) async {
  final CourseDraft? draft = await showCourseEditDialog(
    context,
    title: '加一节课',
    weekday: weekday,
    startPeriod: startPeriod,
    endPeriod: endPeriod,
    confirmLabel: '下一步',
  );
  if (draft == null || !context.mounted) return;

  final String? scope = await showAppDialog<String>(
    context: context,
    builder: (BuildContext _) => AlertDialog(
      title: const Text('怎么加？'),
      content: const Text(
        '临时加只出现在本周（过了这周自动消失）；永久加写进每周课表。',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('temp'),
          child: const Text('临时加（本周）'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop('perm'),
          child: const Text('永久加（每周）'),
        ),
      ],
    ),
  );
  if (scope == null || !context.mounted) return;

  final TimetableRepository repo = ref.read(timetableRepositoryProvider);
  final DateTime now = DateTime.now();
  if (scope == 'temp') {
    await repo.insertOverride(
      CourseOverride(
        id: 0,
        kind: CourseOverrideKind.add,
        weekday: draft.weekday,
        startPeriod: draft.startPeriod,
        endPeriod: draft.endPeriod,
        weekMonday: monday,
        name: draft.name,
        location: draft.location,
        createdAt: now,
      ),
    );
  } else {
    // 永久加的课也要「同课名同色」：把新名字丢进现有课名里重算一遍，
    // 已有课名的分配不会变（assignColorIndexes 对已见名字是稳定的）
    final List<Course> existing = await repo.listCourses();
    final Map<String, int> colorOf = assignColorIndexes(
      <String>[
        for (final Course c in existing) c.name,
        draft.name,
      ],
      kTimetablePaletteSize,
    );
    await repo.insertCourse(
      Course(
        id: 0,
        weekday: draft.weekday,
        startPeriod: draft.startPeriod,
        endPeriod: draft.endPeriod,
        name: draft.name,
        location: draft.location,
        colorIndex: colorOf[draft.name] ?? 0,
        createdAt: now,
      ),
    );
  }
  ref.invalidate(timetableProvider);
}

/// 恢复本周被临时隐藏的格子（删掉本周所有 hide 例外）
Future<void> _restoreHidden(
  BuildContext context,
  WidgetRef ref,
  DateTime monday,
) async {
  final TimetableRepository repo = ref.read(timetableRepositoryProvider);
  final List<CourseOverride> all = await repo.listOverrides();
  for (final CourseOverride o in all) {
    if (o.kind == CourseOverrideKind.hide && _sameWeek(o.weekMonday, monday)) {
      await repo.deleteOverride(o.id);
    }
  }
  ref.invalidate(timetableProvider);
}

/// 「本周已临时隐藏 N 节」的提示条 —— 也是恢复的入口。
class _HiddenBanner extends StatelessWidget {
  const _HiddenBanner({required this.count, required this.onRestore});

  final int count;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Pressable(
      onTap: onRestore,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      highlightColor: scheme.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.visibility_off_outlined,
              size: 15,
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '本周已临时隐藏 $count 节（下周自动回来）',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
            Text(
              '恢复',
              style: text.bodySmall?.copyWith(color: scheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

String _weekdayLabel(int weekday) =>
    const <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日']
        [weekday.clamp(1, 7) - 1];

/// 打开导入流程；回来时刷新课表数据
Future<void> _openImport(BuildContext context) async {
  final ProviderContainer container = ProviderScope.containerOf(context);
  await pushAppPage(context, const ImportTimetablePage());
  // 导入流程里可能写了库（也可能没有），回来一律刷一次 —— 便宜且不会错
  container.invalidate(timetableProvider);
}
