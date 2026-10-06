import 'package:meta/meta.dart';

/// 任务 —— 方案文档 6.4 表 1。
///
/// 「把番茄绑定到具体任务，知道自己专注的时间花在了哪里」——
/// 这是任务功能存在的唯一理由，所以每个任务都带「预估 / 已完成番茄数」。
@immutable
class Task {
  const Task({
    required this.id,
    required this.title,
    this.estimatedPomodoros = 1,
    this.completedPomodoros = 0,
    this.isDone = false,
    this.sortOrder = 0,
    required this.createdAt,
    this.completedAt,
  });

  final int id;
  final String title;

  /// 预估要几个番茄
  final int estimatedPomodoros;

  /// 已经花掉的番茄数
  final int completedPomodoros;

  final bool isDone;

  /// 手动排序权重，越小越靠前
  final int sortOrder;

  final DateTime createdAt;
  final DateTime? completedAt;

  /// 进度 0.0 ~ 1.0。预估为 0 时按已完成算满，避免除零。
  double get progress {
    if (estimatedPomodoros <= 0) return 1;
    return (completedPomodoros / estimatedPomodoros).clamp(0.0, 1.0);
  }

  /// 是否超额完成（已完成 > 预估）
  bool get isOverrun => completedPomodoros > estimatedPomodoros;

  Task copyWith({
    String? title,
    int? estimatedPomodoros,
    int? completedPomodoros,
    bool? isDone,
    int? sortOrder,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) =>
      Task(
        id: id,
        title: title ?? this.title,
        estimatedPomodoros: estimatedPomodoros ?? this.estimatedPomodoros,
        completedPomodoros: completedPomodoros ?? this.completedPomodoros,
        isDone: isDone ?? this.isDone,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
        completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Task &&
          other.id == id &&
          other.title == title &&
          other.estimatedPomodoros == estimatedPomodoros &&
          other.completedPomodoros == completedPomodoros &&
          other.isDone == isDone &&
          other.sortOrder == sortOrder &&
          other.createdAt == createdAt &&
          other.completedAt == completedAt;

  @override
  int get hashCode => Object.hash(
        id,
        title,
        estimatedPomodoros,
        completedPomodoros,
        isDone,
        sortOrder,
        createdAt,
        completedAt,
      );

  @override
  String toString() => 'Task(#$id "$title" $completedPomodoros/$estimatedPomodoros'
      '${isDone ? ' 已完成' : ''})';
}

/// 行映射 —— 表结构见 `AppDatabase._createV2Tables`。
///
/// 时间统一存本地时区 ISO-8601 字符串，与 sessions / timer_snapshot 一致。
/// 布尔用 INTEGER 0/1（SQLite 没有原生布尔）。
class TaskMapper {
  const TaskMapper._();

  static Map<String, Object?> toRow(Task t) => <String, Object?>{
        'id': t.id,
        'title': t.title,
        'estimated_pomodoros': t.estimatedPomodoros,
        'completed_pomodoros': t.completedPomodoros,
        'is_done': t.isDone ? 1 : 0,
        'sort_order': t.sortOrder,
        'created_at': t.createdAt.toIso8601String(),
        'completed_at': t.completedAt?.toIso8601String(),
      };

  /// 新增时用：不含 id，交给 SQLite 自增
  static Map<String, Object?> toInsertRow(Task t) {
    final Map<String, Object?> row = toRow(t)..remove('id');
    return row;
  }

  static Task fromRow(Map<String, Object?> row) => Task(
        id: (row['id'] as int?) ?? 0,
        title: (row['title'] as String?) ?? '',
        estimatedPomodoros: (row['estimated_pomodoros'] as int?) ?? 1,
        completedPomodoros: (row['completed_pomodoros'] as int?) ?? 0,
        isDone: ((row['is_done'] as int?) ?? 0) == 1,
        sortOrder: (row['sort_order'] as int?) ?? 0,
        createdAt: _parseDate(row['created_at']) ?? DateTime.now(),
        completedAt: _parseDate(row['completed_at']),
      );

  static DateTime? _parseDate(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}

/// 列表展示顺序：**未完成在前、已完成沉底**。
///
/// 纯函数，宿主机可直接单测。规则：
///   - 未完成：按 `sortOrder` 升序（用户手动排的）
///   - 已完成：排在最后，按完成时间**倒序**（最近完成的在最上面）
///
/// 为什么不直接按 sortOrder 排完就算：已完成的任务混在中间会干扰视线，
/// 用户关心的是"接下来做什么"。
List<Task> sortedForDisplay(List<Task> tasks) {
  final List<Task> sorted = List<Task>.of(tasks);
  sorted.sort((Task a, Task b) {
    if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
    if (!a.isDone) {
      final int byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      return a.id.compareTo(b.id);
    }
    // 已完成：最近完成的在前；没有完成时间的排在后面
    final DateTime? ca = a.completedAt;
    final DateTime? cb = b.completedAt;
    if (ca == null && cb == null) return a.id.compareTo(b.id);
    if (ca == null) return 1;
    if (cb == null) return -1;
    return cb.compareTo(ca);
  });
  return sorted;
}

/// 新建任务的排序权重：排在所有任务之后。
int nextSortOrder(List<Task> tasks) {
  if (tasks.isEmpty) return 0;
  int max = 0;
  for (final Task t in tasks) {
    if (t.sortOrder > max) max = t.sortOrder;
  }
  return max + 1;
}
