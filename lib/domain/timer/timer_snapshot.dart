import 'timer_engine.dart';
import 'timer_state.dart';

/// `timer_snapshot` 表的行映射 —— 方案文档 6.4 表 4。
///
/// 只做「TimerState ↔ 数据库行」的纯转换，不 import sqflite，
/// 这样映射和恢复逻辑可以在宿主机上直接跑单元测试。
class TimerSnapshotMapper {
  const TimerSnapshotMapper._();

  static TimerState fromRow(Map<String, Object?> row) {
    return TimerState(
      phase: _phaseFrom(row['phase'] as String?),
      startedAt: _dateFrom(row['started_at']),
      plannedSeconds: (row['planned_seconds'] as int?) ?? 25 * 60,
      pausedAt: _dateFrom(row['paused_at']),
      pausedTotal:
          Duration(seconds: (row['paused_total_seconds'] as int?) ?? 0),
      completedPomodoros: (row['round_index'] as int?) ?? 0,
      taskId: row['task_id'] as int?,
    );
  }

  static Map<String, Object?> toRow(TimerState s, {int id = 1}) {
    return <String, Object?>{
      'id': id,
      'phase': s.phase.name,
      'started_at': s.startedAt?.toIso8601String(),
      'planned_seconds': s.plannedSeconds,
      'paused_at': s.pausedAt?.toIso8601String(),
      'paused_total_seconds': s.pausedTotal.inSeconds,
      // M5 起真正使用：本次专注绑定的任务（未绑定为 null）
      'task_id': s.taskId,
      'round_index': s.completedPomodoros,
    };
  }

  static TimerPhase _phaseFrom(String? name) => TimerPhase.values.firstWhere(
        (TimerPhase p) => p.name == name,
        orElse: () => TimerPhase.focus,
      );

  static DateTime? _dateFrom(Object? iso) =>
      iso is String ? DateTime.tryParse(iso) : null;
}

/// 快照恢复的结果。
class SnapshotRecovery {
  const SnapshotRecovery({
    required this.state,
    required this.hadSnapshot,
    required this.expiredDuringAbsence,
  });

  /// 恢复后应当处于的状态
  final TimerState state;

  /// 磁盘上是否存在过快照
  final bool hadSnapshot;

  /// 离开期间计时是否已走完（走完按"已完成"处理，M4 起补记 sessions）
  final bool expiredDuringAbsence;
}

/// 快照恢复决策（纯函数）—— 方案文档 6.5② 第三层"回到前台时补偿"。
///
/// 规则（与绝对时间戳设计配套，方案 6.5①）：
/// - 无快照 → 全新初始状态
/// - 快照未开始（idle）→ 原样恢复
/// - 快照暂停中 → 原样恢复（暂停=时间冻结在 pausedAt，不存在"过期"）
/// - 快照计时中且未走完 → 原样恢复，剩余时间由绝对时间戳实时算出
/// - 快照计时中但已走完 → 按"已完成"处理：计入专注数、流转到下一阶段（不自动开始）
SnapshotRecovery recoverFromSnapshot({
  required Map<String, Object?>? row,
  required DateTime now,
  required TimerConfig config,
}) {
  final TimerState fresh = TimerState.idle(
    phase: TimerPhase.focus,
    plannedSeconds: config.secondsFor(TimerPhase.focus),
  );
  if (row == null) {
    return SnapshotRecovery(
      state: fresh,
      hadSnapshot: false,
      expiredDuringAbsence: false,
    );
  }

  final TimerState s = TimerSnapshotMapper.fromRow(row);

  if (s.isIdle || s.isPaused) {
    return SnapshotRecovery(
      state: s,
      hadSnapshot: true,
      expiredDuringAbsence: false,
    );
  }

  if (!s.isExpiredAt(now)) {
    return SnapshotRecovery(
      state: s,
      hadSnapshot: true,
      expiredDuringAbsence: false,
    );
  }

  final int completed = TimerEngine.completedAfter(s.phase, s.completedPomodoros);
  final TimerPhase next = TimerEngine.nextPhase(
    current: s.phase,
    completedPomodorosAfter: completed,
    config: config,
  );

  return SnapshotRecovery(
    state: TimerState.idle(
      phase: next,
      plannedSeconds: config.secondsFor(next),
      completedPomodoros: completed,
    ),
    hadSnapshot: true,
    expiredDuringAbsence: true,
  );
}
