import '../../domain/settings/reminder_settings.dart';
import '../../domain/timer/timer_engine.dart';
import '../../domain/timer/timer_state.dart';

/// Dart ↔ 原生前台服务的状态协议。
///
/// 纯函数、无通道依赖，宿主机可直接单测。key 与
/// `TimerForegroundService.kt` 里的 KEY_* 常量一一对应，改动必须双侧同步。
///
/// 时间统一用「epoch 毫秒」传输（通道对 int 无损），Dart 侧再转 DateTime。
class TimerServiceProtocol {
  const TimerServiceProtocol._();

  static Map<String, Object?> toMap(
    TimerState s,
    TimerConfig c, {
    ReminderSettings reminder = const ReminderSettings(),
  }) {
    return <String, Object?>{
      'phase': s.phase.name,
      'startedAt': s.startedAt?.millisecondsSinceEpoch,
      'plannedSeconds': s.plannedSeconds,
      'pausedAt': s.pausedAt?.millisecondsSinceEpoch,
      'pausedTotalSeconds': s.pausedTotal.inSeconds,
      'completed': s.completedPomodoros,
      'autoStart': c.autoStartNext,
      'focusMin': c.focusMinutes,
      'shortMin': c.shortBreakMinutes,
      'longMin': c.longBreakMinutes,
      'interval': c.longBreakInterval,
      // M4 提醒开关：原生服务据此决定到点用哪个通知渠道
      // （响铃+震动 / 只响铃 / 静默）。注意这只影响"响不响"，
      // 不影响精确闹钟是否排程 —— 静默时到点依然出通知。
      'remindSound': reminder.soundEnabled,
      'remindVibrate': reminder.effectiveVibrate,
    };
  }

  /// 原生回传的状态 → TimerState。空数据 / phase 不认识 → null。
  static TimerState? fromMap(Map<Object?, Object?>? map) {
    if (map == null) return null;
    final String phaseName = map['phase'] as String? ?? '';
    final TimerPhase phase = TimerPhase.values.firstWhere(
      (TimerPhase p) => p.name == phaseName,
      orElse: () => TimerPhase.focus,
    );
    final int? startedAt = (map['startedAt'] as num?)?.toInt();
    final int planned = (map['plannedSeconds'] as num?)?.toInt() ?? 25 * 60;
    final int? pausedAt = (map['pausedAt'] as num?)?.toInt();
    final int pausedTotal = (map['pausedTotalSeconds'] as num?)?.toInt() ?? 0;
    final int completed = (map['completed'] as num?)?.toInt() ?? 0;

    if (startedAt == null || startedAt <= 0) {
      // 原生只有"未开始"的空状态 → 无需恢复
      return null;
    }

    return TimerState(
      phase: phase,
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt),
      plannedSeconds: planned,
      pausedAt: (pausedAt != null && pausedAt > 0)
          ? DateTime.fromMillisecondsSinceEpoch(pausedAt)
          : null,
      pausedTotal: Duration(seconds: pausedTotal),
      completedPomodoros: completed,
    );
  }

  /// 通知/日志里用的 mm:ss（与主界面同一格式）
  static String countdownText(int remainingSeconds) {
    final int m = remainingSeconds ~/ 60;
    final int s = remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// 本阶段结束的绝对时刻（epoch 毫秒）；**未开始 / 暂停中返回 null**。
  ///
  /// 与 Kotlin 侧 `TimerForegroundService.phaseEndMillis()` 同一公式：
  /// ```
  /// startedAt + 累计暂停时长 + 计划时长
  /// ```
  /// M3 阶段三的精确闹钟就排在这一时刻
  /// （`AlarmManager.setExactAndAllowWhileIdle(RTC_WAKEUP, ...)`）。
  ///
  /// 返回 null 的语义是「**应当撤掉已排的闹钟**」——暂停期间时间被冻结，
  /// 若闹钟留着就会在暂停时误响。
  static int? phaseEndMillis(TimerState s) {
    final DateTime? start = s.startedAt;
    if (start == null) return null; // 未开始
    if (s.pausedAt != null) return null; // 暂停中：冻结，不排闹钟
    return start.millisecondsSinceEpoch +
        (s.pausedTotal.inSeconds + s.plannedSeconds) * 1000;
  }
}
