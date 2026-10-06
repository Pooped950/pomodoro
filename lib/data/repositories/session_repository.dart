import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/timer/session_record.dart';
import '../../domain/timer/timer_state.dart';

/// `sessions` 表的读写 —— 方案文档 6.4 表 2。
///
/// **统计的唯一数据源**：方案既定"统计不建表，从 sessions 实时聚合"，
/// 所以这里只提供写入 + 按时间段查询两种能力，聚合口径由调用方决定。
class SessionRepository {
  SessionRepository(this._db);

  final Database _db;

  /// 写入一条记录。
  ///
  /// 用 `INSERT OR IGNORE`：一次计时由 `(phase, started_at)` 唯一确定，
  /// Dart 侧与原生服务可能同时推进阶段、各自补写一次，
  /// 重复的那条会被唯一索引丢弃，不会产生重复统计。
  Future<void> insert(SessionRecord r) async {
    await _db.insert(
      'sessions',
      SessionMapper.toRow(r),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 某天**完整走完的专注**条数 —— 主界面「今日 N / 8」用的就是这个。
  /// 休息阶段与跳过/放弃的记录都不计入。
  Future<int> completedFocusCountOn(DateTime day) async {
    final ({DateTime from, DateTime to}) range = dayRange(day);
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM sessions '
      'WHERE phase = ? AND is_completed = 1 '
      'AND started_at >= ? AND started_at < ?',
      <Object>[
        TimerPhase.focus.name,
        range.from.toIso8601String(),
        range.to.toIso8601String(),
      ],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// 某天的全部记录，按开始时间升序
  Future<List<SessionRecord>> onDay(DateTime day) async {
    final ({DateTime from, DateTime to}) range = dayRange(day);
    return inRange(range.from, range.to);
  }

  /// `[from, to)` 区间内的全部记录，按开始时间升序。
  ///
  /// 统计页用它**一次取回整段区间**再在内存里聚合，而不是按天查 N 次 ——
  /// 7 天柱状图 + 今日概览 + 任务分布三块数据来自同一批记录，
  /// 分三次查就是三次数据库往返、而且三块数据可能取到不同时刻的快照。
  ///
  /// 左闭右开：`from <= started_at < to`。ISO-8601 字符串的字典序即时间序，
  /// 所以直接字符串比较就等价于按时间比较（见 [dayRange] 的说明）。
  Future<List<SessionRecord>> inRange(DateTime from, DateTime to) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'sessions',
      where: 'started_at >= ? AND started_at < ?',
      whereArgs: <Object>[
        from.toIso8601String(),
        to.toIso8601String(),
      ],
      orderBy: 'started_at ASC',
    );
    return rows.map(SessionMapper.fromRow).toList();
  }
}

/// 依赖注入：main() 里数据库就绪后用 overrideWithValue 注入真实实例。
/// 未注入时直接 read 会抛错，避免"以为写进去了其实没写"。
final sessionRepositoryProvider = Provider<SessionRepository>(
  (Ref ref) => throw UnimplementedError(
    'sessionRepositoryProvider 必须在 main() 里 override',
  ),
);
