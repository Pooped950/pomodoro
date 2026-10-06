import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/timer/timer_snapshot.dart';
import '../../domain/timer/timer_state.dart';

/// `timer_snapshot` 单行表的读写 —— 方案文档 6.4 表 4。
///
/// 每次计时状态变化都整行覆写（id 恒为 1）；表里永远只反映"最新一次"计时。
class TimerSnapshotRepository {
  TimerSnapshotRepository(this._db);

  final Database _db;

  /// 读快照行；无快照返回 null
  Future<Map<String, Object?>?> load() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'timer_snapshot',
      where: 'id = ?',
      whereArgs: <Object>[1],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// 整行覆写为当前状态
  Future<void> save(TimerState state) async {
    await _db.insert(
      'timer_snapshot',
      TimerSnapshotMapper.toRow(state),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

/// 依赖注入：main() 里数据库就绪后用 overrideWith 注入真实实例。
/// 直接 read 未注入的实例会抛错，避免悄悄写不进磁盘。
final timerSnapshotRepositoryProvider = Provider<TimerSnapshotRepository>(
  (Ref ref) => throw UnimplementedError(
    'timerSnapshotRepositoryProvider 必须在 main() 里 override',
  ),
);
