import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../domain/task/task.dart';
import '../../providers/task_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_context_menu.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/pressable.dart';

/// 任务视图 —— M5-①
///
/// 「把番茄绑定到具体任务，知道自己专注的时间花在了哪里」。
/// 列表分两段：**进行中**（按手动排序）在上，**已完成**沉底置灰。
///
/// ## 为什么叫 View 不叫 Page（2026-10-06 改）
///
/// 它不再独占一个底部标签了 —— 用户把「任务」和「统计」合并成了导航第二格，
/// 顶部两个小标签切换（见 `TaskStatsPage`）。所以原来那行
/// 「任务 + 新建按钮」的标题行被拿掉：**标签本身就是标题**，
/// 再画一行"任务"就重复了。新建入口随之搬到容器页顶部，
/// 通过公开的 [showTaskEditor] 唤起。
///
/// 自己的 `SafeArea` / `Center` / `ConstrainedBox` 保留着 ——
/// 外面再套一层同样的壳没有副作用（`SafeArea` 会消费掉安全区，内层拿到的是 0），
/// 换来的是这个视图**可以单独拿出来跑**（预览 / 单测）而不用再配壳。
class TasksView extends ConsumerWidget {
  const TasksView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Task> tasks = ref.watch(sortedTasksProvider);
    final TaskListNotifier notifier = ref.read(taskListProvider.notifier);

    final List<Task> active =
        tasks.where((Task t) => !t.isDone).toList(growable: false);
    final List<Task> done =
        tasks.where((Task t) => t.isDone).toList(growable: false);

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
              if (tasks.isEmpty)
                const _EmptyHint()
              else ...<Widget>[
                if (active.isNotEmpty)
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: <Widget>[
                        for (int i = 0; i < active.length; i++) ...<Widget>[
                          if (i > 0) const _RowDivider(),
                          _TaskRow(
                            task: active[i],
                            onToggle: () => notifier.toggleDone(active[i]),
                            onMore: (Rect anchor) => _openTaskMenu(
                              context,
                              ref,
                              active[i],
                              anchor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                if (done.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.section),
                  _SectionLabel('已完成 ${done.length}'),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: <Widget>[
                        for (int i = 0; i < done.length; i++) ...<Widget>[
                          if (i > 0) const _RowDivider(),
                          _TaskRow(
                            task: done[i],
                            onToggle: () => notifier.toggleDone(done[i]),
                            onMore: (Rect anchor) => _openTaskMenu(
                              context,
                              ref,
                              done[i],
                              anchor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 某个任务的「更多」菜单 —— **贴住「三个点」弹出**的玻璃上下文菜单。
  ///
  /// ## 三代演进（都是按用户实测反馈改的）
  ///
  /// 1. `PopupMenuButton`：用户说「动效设计过于丑陋，要丝滑的滑动补帧跳出来」
  /// 2. 底部玻璃弹层：用户说「理应是在三个点附近弹出，而非下方弹出」
  /// 3. **贴锚点的上下文菜单**（当前）：既有"从按钮里长出来"的动画，位置也对
  ///
  /// 第 2 版是我理解偏了 —— 底部弹层适合**选择类**操作（一列可选项，
  /// 比如任务选择器），而"编辑 / 删除这一条"是**针对刚点的那个元素**的动作：
  /// 菜单跑到底部，手指和视线都要跨越整屏，还看不出"这个菜单属于哪一条"。
  ///
  /// [anchor] 是「三个点」按钮在**全局坐标**下的矩形，由 [_TaskRow] 量出来。
  ///
  /// ⚠️ 菜单是 `await` 出来的，期间页面可能已经被销毁。所以 notifier 在
  /// await **之前**就抓好，之后一律用这个引用，不再碰 `ref`。
  Future<void> _openTaskMenu(
    BuildContext context,
    WidgetRef ref,
    Task task,
    Rect anchor,
  ) async {
    final TaskListNotifier notifier = ref.read(taskListProvider.notifier);

    final String? action = await showAppContextMenu<String>(
      context: context,
      anchor: anchor,
      items: const <AppContextMenuItem<String>>[
        AppContextMenuItem<String>(
          value: 'edit',
          label: '编辑',
          icon: Icons.edit_rounded,
        ),
        AppContextMenuItem<String>(
          value: 'delete',
          label: '删除',
          icon: Icons.delete_outline_rounded,
          destructive: true,
        ),
      ],
    );

    if (action == null) return; // 点外部 / 返回 = 取消
    // await 之后 context 可能已经失效（页面被销毁），必须检查
    if (!context.mounted) return;
    if (action == 'edit') {
      await showTaskEditor(context, notifier, existing: task);
    } else if (action == 'delete') {
      await notifier.delete(task);
    }
  }
}

/// 唤起「新建 / 编辑任务」对话框。传 [existing] 就是编辑。
///
/// ## 为什么是**公开的顶层函数**（2026-10-06 改）
///
/// 唤起它的入口已经不在这个文件里了 —— 第二页顶部那排「任务 / 统计」标签
/// 右边的「+」由容器页 `TaskStatsPage` 提供。提成顶层函数两边共用一份，
/// 不会出现"从列表里点编辑"和"从 + 点新建"弹出两个长得不一样的框。
///
/// 参数收的是 [notifier] 而不是 `WidgetRef`：调用方（菜单那条路径）
/// 是 `await` 之后才走到这里的，那时页面可能已经销毁，再 `ref.read` 会抛异常。
///
/// 用 `showAppDialog` 而不是 `showDialog`：后者进出场写死 150ms，
/// 在别的动画都放到 380~420ms 之后会显得"啪"地砸出来（详见其注释）。
Future<void> showTaskEditor(
  BuildContext context,
  TaskListNotifier notifier, {
  Task? existing,
}) async {
  final ({String title, int estimated})? result =
      await showAppDialog<({String title, int estimated})>(
    context: context,
    builder: (BuildContext _) => TaskEditorDialog(existing: existing),
  );
  if (result == null) return;

  if (existing == null) {
    await notifier.add(result.title, result.estimated);
  } else {
    await notifier.edit(existing, result.title, result.estimated);
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

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
              Icons.check_circle_outline,
              color: scheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(height: AppSpacing.item),
          Text('还没有任务', style: text.titleMedium),
          const SizedBox(height: AppSpacing.tight),
          Text(
            '点右上角「+」建一个任务，设定预估番茄数。'
            '之后就能把每次专注绑定到它，看清时间花在了哪里。',
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.6),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: AppSpacing.tight),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: AppSpacing.item,
      endIndent: AppSpacing.item,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
    );
  }
}

/// 一行任务：勾选框 + 标题 + 番茄进度 + 更多按钮
///
/// 做成 StatefulWidget 只是为了**持有「三个点」按钮的 GlobalKey** ——
/// 菜单要贴住这个按钮弹出，就得拿到它在全局坐标下的矩形。
/// 用 GlobalKey 而不是 `context.findRenderObject()`：后者拿到的是
/// 子树里第一个 RenderObject，不一定是按钮本身（Pressable 内部还套了几层），
/// 尺寸会偏，菜单就会贴歪。
class _TaskRow extends StatefulWidget {
  const _TaskRow({
    required this.task,
    required this.onToggle,
    required this.onMore,
  });

  final Task task;
  final VoidCallback onToggle;

  /// 点「三个点」—— 回传按钮的全局矩形，由页面弹上下文菜单
  final ValueChanged<Rect> onMore;

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  final GlobalKey _moreKey = GlobalKey();

  void _handleMore() {
    final BuildContext? ctx = _moreKey.currentContext;
    final RenderObject? ro = ctx?.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return;
    widget.onMore(ro.localToGlobal(Offset.zero) & ro.size);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    final Task task = widget.task;

    // 已完成整行置灰，但仍可操作（取消勾选 / 删除）
    final double dim = task.isDone ? 0.45 : 1.0;
    final Color titleColor =
        scheme.onSurface.withValues(alpha: task.isDone ? 0.45 : 0.95);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.tight, 10, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 勾选框
          IconButton(
            onPressed: widget.onToggle,
            icon: Icon(
              task.isDone
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: task.isDone
                  ? scheme.primary.withValues(alpha: 0.6)
                  : scheme.onSurface.withValues(alpha: 0.35),
            ),
            tooltip: task.isDone ? '标记为未完成' : '标记为已完成',
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    task.title,
                    style: text.bodyMedium?.copyWith(
                      color: titleColor,
                      decoration:
                          task.isDone ? TextDecoration.lineThrough : null,
                      decorationColor: scheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      // 番茄进度：细条 + 数字
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: LinearProgressIndicator(
                            value: task.progress,
                            minHeight: 4,
                            backgroundColor:
                                scheme.onSurface.withValues(alpha: 0.08),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              scheme.primary.withValues(alpha: 0.55 * dim),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${task.completedPomodoros} / ${task.estimatedPomodoros}',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.5 * dim),
                          fontFeatures: const <FontFeature>[
                            FontFeature('tnum'),
                          ],
                        ),
                      ),
                      if (task.isOverrun)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            '超额',
                            style: text.bodySmall?.copyWith(
                              color: scheme.primary.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 「更多」：点开**贴住这个按钮**弹出的上下文菜单。
          // 用 Pressable 而不是 IconButton —— 统一按压反馈，
          // 而且把点击热区做到 40×40（图标只有 20），手指更好点。
          // key 挂在 SizedBox 上：菜单要靠它的全局矩形来定位
          Pressable(
            onTap: _handleMore,
            highlightColor: scheme.onSurface.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: SizedBox(
              key: _moreKey,
              width: 40,
              height: 40,
              child: Icon(
                Icons.more_horiz_rounded,
                size: 20,
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 新建 / 编辑对话框：标题 + 预估番茄数
class TaskEditorDialog extends StatefulWidget {
  const TaskEditorDialog({super.key, this.existing});

  final Task? existing;

  @override
  State<TaskEditorDialog> createState() => TaskEditorDialogState();
}

class TaskEditorDialogState extends State<TaskEditorDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.existing?.title ?? '');
  late int _estimated = widget.existing?.estimatedPomodoros ?? 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.existing != null;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return AlertDialog(
      title: Text(_isEdit ? '编辑任务' : '新建任务'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '任务名称',
              hintText: '例如：写方案',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.item),
          Row(
            children: <Widget>[
              Expanded(
                child: Text('预估番茄数', style: text.bodyMedium),
              ),
              IconButton(
                onPressed: _estimated > 1
                    ? () => setState(() => _estimated -= 1)
                    : null,
                icon: const Icon(Icons.remove_rounded),
                visualDensity: VisualDensity.compact,
              ),
              Text(
                '$_estimated',
                style: text.titleMedium?.copyWith(
                  color: scheme.primary,
                  fontFeatures: const <FontFeature>[FontFeature('tnum')],
                ),
              ),
              IconButton(
                onPressed: _estimated < 20
                    ? () => setState(() => _estimated += 1)
                    : null,
                icon: const Icon(Icons.add_rounded),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isEdit ? '保存' : '创建'),
        ),
      ],
    );
  }

  void _submit() {
    final String title = _controller.text.trim();
    // 空标题直接忽略（不弹错误、不关闭对话框），避免建出无名任务
    if (title.isEmpty) return;
    Navigator.of(context).pop((title: title, estimated: _estimated));
  }
}
