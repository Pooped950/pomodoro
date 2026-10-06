import 'package:meta/meta.dart';

import 'timer_state.dart';

/// 一条专注 / 休息记录 —— 方案文档 6.4 表 2。
///
/// **统计的唯一数据源**（方案既定决策：统计不建表，从 sessions 实时聚合）。
@immutable
class SessionRecord {
  const SessionRecord({
    required this.phase,
    required this.plannedSeconds,
    required this.actualSeconds,
    required this.startedAt,
    required this.isCompleted,
    this.taskId,
    this.endedAt,
  });

  final TimerPhase phase;

  /// 计划时长（秒）
  final int plannedSeconds;

  /// 实际时长（秒），**封顶到 [plannedSeconds]**
  final int actualSeconds;

  final DateTime startedAt;
  final DateTime? endedAt;

  /// 是否完整走完。跳过 / 放弃为 false。
  final bool isCompleted;

  /// 关联任务，未绑定为 null
  final int? taskId;

  /// 是否计入"完成了一个番茄"（统计口径：专注 + 完整走完）
  bool get countsAsPomodoro =>
      phase == TimerPhase.focus && isCompleted;
}

/// 行映射 —— 表结构见 `AppDatabase._createV2Tables`。
///
/// 时间统一存**本地时区**的 ISO-8601 字符串（与 `timer_snapshot` 一致）。
/// 这样"按天范围查询"可以直接用字符串比较：ISO-8601 的字典序即时间序，
/// 且长度相同时逐字符比较等价于按时间比较。
class SessionMapper {
  const SessionMapper._();

  static Map<String, Object?> toRow(SessionRecord r) => <String, Object?>{
        'task_id': r.taskId,
        'phase': r.phase.name,
        'planned_seconds': r.plannedSeconds,
        'actual_seconds': r.actualSeconds,
        'started_at': r.startedAt.toIso8601String(),
        'ended_at': r.endedAt?.toIso8601String(),
        'is_completed': r.isCompleted ? 1 : 0,
      };

  static SessionRecord fromRow(Map<String, Object?> row) => SessionRecord(
        phase: TimerPhase.values.firstWhere(
          (TimerPhase p) => p.name == row['phase'],
          orElse: () => TimerPhase.focus,
        ),
        plannedSeconds: (row['planned_seconds'] as int?) ?? 0,
        actualSeconds: (row['actual_seconds'] as int?) ?? 0,
        startedAt: DateTime.parse(row['started_at']! as String),
        endedAt: row['ended_at'] == null
            ? null
            : DateTime.parse(row['ended_at']! as String),
        isCompleted: ((row['is_completed'] as int?) ?? 0) == 1,
        taskId: row['task_id'] as int?,
      );
}

/// 由「即将被替换掉的那次计时」推断一条 session 记录。
///
/// 纯函数，宿主机可直接单测。返回 null 表示这次状态变化不该产生记录
/// （本来就没在计时 —— 例如从未开始状态直接开始下一阶段）。
///
/// [endedAt] 是这次计时被判定结束的时刻：
///   - 自然到点：到点那一刻
///   - 跳过 / 放弃：用户点下去那一刻
///   - 原生服务在后台推进了阶段：新阶段的 startedAt
///
/// [completed] 对应方案 6.4 表 2 的 `is_completed`。
///
/// ⚠️ [actualSeconds] **必须封顶到 plannedSeconds**：App 被系统冻结时，
/// 到点判定可能晚很多才发生，不封顶会写出"25 分钟的番茄实际跑了 40 分钟"。
SessionRecord? sessionForReplacedState({
  required TimerState previous,
  required DateTime endedAt,
  required bool completed,
  int? taskId,
}) {
  final DateTime? start = previous.startedAt;
  if (start == null) return null; // 本来就没在计时

  final int actual = previous.elapsedAt(endedAt).inSeconds;
  return SessionRecord(
    phase: previous.phase,
    plannedSeconds: previous.plannedSeconds,
    actualSeconds:
        actual > previous.plannedSeconds ? previous.plannedSeconds : actual,
    startedAt: start,
    endedAt: endedAt,
    isCompleted: completed,
    taskId: taskId,
  );
}

/// 某一天的起止时刻（本地时区），左闭右开。纯函数，便于单测。
({DateTime from, DateTime to}) dayRange(DateTime day) {
  final DateTime from = DateTime(day.year, day.month, day.day);
  return (from: from, to: from.add(const Duration(days: 1)));
}
