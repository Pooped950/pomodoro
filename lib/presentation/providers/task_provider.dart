import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../domain/task/task.dart';

/// 任务列表状态 —— 启动读库，增删改后同步内存与磁盘。
///
/// 与 `TimerConfigNotifier` 同一套做法：仓库未注入（纯逻辑测试环境）时静默跳过，
/// 界面照常渲染空列表。
class TaskListNotifier extends Notifier<List<Task>> {
  @override
  List<Task> build() {
    unawaited(_load());
    return const <Task>[];
  }

  Future<void> _load() async {
    try {
      state = await ref.read(taskRepositoryProvider).listAll();
    } catch (_) {
      // 仓库未注入 / 读失败 → 保持空列表
    }
  }

  /// 供页面下拉刷新、或从别的页面回来时调用
  Future<void> refresh() => _load();

  Future<void> add(String title, int estimatedPomodoros) async {
    final String trimmed = title.trim();
    if (trimmed.isEmpty) return; // 空标题不建任务，也不弹错误 —— 直接忽略

    final Task t = Task(
      id: 0, // 交给 SQLite 自增
      title: trimmed,
      estimatedPomodoros: estimatedPomodoros < 1 ? 1 : estimatedPomodoros,
      sortOrder: nextSortOrder(state),
      createdAt: DateTime.now(),
    );

    try {
      await ref.read(taskRepositoryProvider).insert(t);
      await _load();
    } catch (_) {
      // 写失败不拖垮界面
    }
  }

  /// 编辑标题与预估番茄数
  Future<void> edit(Task task, String title, int estimatedPomodoros) async {
    final String trimmed = title.trim();
    if (trimmed.isEmpty) return;
    await _update(task.copyWith(
      title: trimmed,
      estimatedPomodoros: estimatedPomodoros < 1 ? 1 : estimatedPomodoros,
    ));
  }

  /// 勾选 / 取消勾选完成
  Future<void> toggleDone(Task task) async {
    final bool nowDone = !task.isDone;
    await _update(task.copyWith(
      isDone: nowDone,
      completedAt: nowDone ? DateTime.now() : null,
      clearCompletedAt: !nowDone,
    ));
  }

  Future<void> delete(Task task) async {
    // 先就地移除，删除要立刻有反馈
    state = <Task>[
      for (final Task t in state)
        if (t.id != task.id) t,
    ];
    try {
      await ref.read(taskRepositoryProvider).delete(task.id);
    } catch (_) {
      await _load(); // 落盘失败就回滚成磁盘真实状态
    }
  }

  Future<void> _update(Task next) async {
    // 先就地更新内存态：勾选 / 改名要**立刻**有反馈，不等数据库往返
    state = <Task>[
      for (final Task t in state)
        if (t.id == next.id) next else t,
    ];
    try {
      await ref.read(taskRepositoryProvider).update(next);
    } catch (_) {
      await _load();
    }
  }
}

final taskListProvider = NotifierProvider<TaskListNotifier, List<Task>>(
  TaskListNotifier.new,
);

/// 展示顺序：未完成在前、已完成沉底。
/// 页面 watch 这个而不是 [taskListProvider]，排序规则就统一在一处。
final sortedTasksProvider = Provider<List<Task>>((Ref ref) {
  return sortedForDisplay(ref.watch(taskListProvider));
});

/// 计时页「当前选中的任务」—— 开始专注时要绑定的那个。
///
/// 刻意与 `TimerState.taskId` 分开：
///   - 这个是"用户此刻选了哪个"，随时可改
///   - `TimerState.taskId` 是"本次专注绑定的任务"，在 `start()` 时捕获
/// 两者混在一起的话，专注到一半去换个选中项，正在跑的这次专注归属就变了。
///
/// 会落库，所以重启后还停在上次选的任务上。
class SelectedTaskIdNotifier extends Notifier<int?> {
  @override
  int? build() {
    unawaited(_restore());
    return null;
  }

  Future<void> _restore() async {
    try {
      final String? raw = await ref
          .read(settingsRepositoryProvider)
          .readString(SettingsRepository.keySelectedTaskId);
      if (raw == null || raw.isEmpty) return;
      final int? id = int.tryParse(raw);
      if (id != null) state = id;
    } catch (_) {
      // 仓库未注入 / 读失败 → 保持未选
    }
  }

  void select(int? taskId) {
    if (taskId == state) return;
    state = taskId;
    unawaited(_persist(taskId));
  }

  Future<void> _persist(int? taskId) async {
    try {
      await ref.read(settingsRepositoryProvider).writeString(
            SettingsRepository.keySelectedTaskId,
            taskId?.toString() ?? '',
          );
    } on UnimplementedError {
      // provider 未注入（纯逻辑测试环境）
    } catch (_) {
      // 落盘失败不拖垮界面
    }
  }
}

final selectedTaskIdProvider = NotifierProvider<SelectedTaskIdNotifier, int?>(
  SelectedTaskIdNotifier.new,
);

/// 当前选中的任务对象；未选 / 任务已被删掉时为 null。
///
/// ⚠️ **必须先无条件 `watch(taskListProvider)` 再判断 id**。
/// 曾经写成"先判断 id 为 null 就 return"，结果没选任务时 `taskListProvider`
/// 从头到尾没被 watch 过、也就没被初始化 —— 之后别处 `ref.read` 它只会拿到
/// "刚 build、异步加载还没回来"的空列表。表现是**第一次打开任务选择器永远是空的**
/// （2026-10-05 模拟器实测踩到）。
final selectedTaskProvider = Provider<Task?>((Ref ref) {
  final List<Task> all = ref.watch(taskListProvider);
  final int? id = ref.watch(selectedTaskIdProvider);
  if (id == null) return null;
  for (final Task t in all) {
    if (t.id == id) return t;
  }
  return null;
});
