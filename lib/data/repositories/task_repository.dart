import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/task/task.dart';

/// `tasks` 表的读写 —— 方案文档 6.4 表 1。
///
/// 刻意只提供"取全部 + 增删改"，**不做排序和过滤** ——
/// 展示顺序交给纯函数 [sortedForDisplay]，这样"怎么排"可以直接单测，
/// 不用连数据库。
class TaskRepository {
  TaskRepository(this._db);

  final Database _db;

  /// 全部任务（按 sort_order 粗排；最终展示顺序由 [sortedForDisplay] 决定）
  Future<List<Task>> listAll() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'tasks',
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(TaskMapper.fromRow).toList();
  }

  /// 返回新任务的 id
  Future<int> insert(Task t) => _db.insert('tasks', TaskMapper.toInsertRow(t));

  Future<void> update(Task t) async {
    final Map<String, Object?> row = TaskMapper.toRow(t)..remove('id');
    await _db.update(
      'tasks',
      row,
      where: 'id = ?',
      whereArgs: <Object>[t.id],
    );
  }

  Future<void> delete(int id) =>
      _db.delete('tasks', where: 'id = ?', whereArgs: <Object>[id]);

  /// 给任务的已完成番茄数 +1。
  /// 专注阶段完整走完时调用（M5-②），与 sessions 落库是同一个时机。
  Future<void> incrementCompleted(int taskId) async {
    await _db.rawUpdate(
      'UPDATE tasks SET completed_pomodoros = completed_pomodoros + 1 '
      'WHERE id = ?',
      <Object>[taskId],
    );
  }
}

/// 依赖注入：main() 里数据库就绪后用 overrideWithValue 注入真实实例。
final taskRepositoryProvider = Provider<TaskRepository>(
  (Ref ref) => throw UnimplementedError(
    'taskRepositoryProvider 必须在 main() 里 override',
  ),
);
