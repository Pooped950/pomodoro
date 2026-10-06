import 'package:meta/meta.dart';

import 'timer_state.dart';

/// 计时配置（用户可在设置页修改，P0 阶段先用默认值）。
@immutable
class TimerConfig {
  const TimerConfig({
    this.focusMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.longBreakInterval = 4,
    this.autoStartNext = false,
  });

  /// 专注时长（分钟）
  final int focusMinutes;

  /// 短休息时长（分钟）
  final int shortBreakMinutes;

  /// 长休息时长（分钟）
  final int longBreakMinutes;

  /// 每完成几个专注后进入长休息
  final int longBreakInterval;

  /// 阶段结束后是否自动开始下一个阶段
  final bool autoStartNext;

  /// 某个阶段对应的秒数
  int secondsFor(TimerPhase phase) => switch (phase) {
        TimerPhase.focus => focusMinutes * 60,
        TimerPhase.shortBreak => shortBreakMinutes * 60,
        TimerPhase.longBreak => longBreakMinutes * 60,
      };

  TimerConfig copyWith({
    int? focusMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? longBreakInterval,
    bool? autoStartNext,
  }) =>
      TimerConfig(
        focusMinutes: focusMinutes ?? this.focusMinutes,
        shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
        longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
        longBreakInterval: longBreakInterval ?? this.longBreakInterval,
        autoStartNext: autoStartNext ?? this.autoStartNext,
      );

  /// 序列化到 `settings` 表的 value 列（M4）
  Map<String, Object?> toJson() => <String, Object?>{
        'focusMinutes': focusMinutes,
        'shortBreakMinutes': shortBreakMinutes,
        'longBreakMinutes': longBreakMinutes,
        'longBreakInterval': longBreakInterval,
        'autoStartNext': autoStartNext,
      };

  /// 从 JSON 还原。
  ///
  /// **缺字段 / 类型不对一律回退到构造函数默认值** —— 老版本存下的 JSON 字段更少、
  /// 或库里的值被手工改坏时，既不能崩，也不能把缺失值读成 0
  /// （那会让专注时长变成 0 分钟）。
  factory TimerConfig.fromJson(Map<String, Object?> json) {
    const TimerConfig d = TimerConfig();
    return TimerConfig(
      focusMinutes: _asInt(json['focusMinutes']) ?? d.focusMinutes,
      shortBreakMinutes:
          _asInt(json['shortBreakMinutes']) ?? d.shortBreakMinutes,
      longBreakMinutes: _asInt(json['longBreakMinutes']) ?? d.longBreakMinutes,
      longBreakInterval:
          _asInt(json['longBreakInterval']) ?? d.longBreakInterval,
      autoStartNext: _asBool(json['autoStartNext']) ?? d.autoStartNext,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimerConfig &&
          other.focusMinutes == focusMinutes &&
          other.shortBreakMinutes == shortBreakMinutes &&
          other.longBreakMinutes == longBreakMinutes &&
          other.longBreakInterval == longBreakInterval &&
          other.autoStartNext == autoStartNext;

  @override
  int get hashCode => Object.hash(
        focusMinutes,
        shortBreakMinutes,
        longBreakMinutes,
        longBreakInterval,
        autoStartNext,
      );
}

/// 阶段流转规则（纯函数，无副作用，可单独测试）。
class TimerEngine {
  const TimerEngine._();

  /// 计算下一个阶段。
  ///
  /// [completedPomodorosAfter] 是**本次专注计入之后**的累计专注数，
  /// 也就是说：刚做完第 4 个专注时传入 4，会返回长休息。
  static TimerPhase nextPhase({
    required TimerPhase current,
    required int completedPomodorosAfter,
    required TimerConfig config,
  }) {
    if (current.isBreak) return TimerPhase.focus;

    final int interval =
        config.longBreakInterval <= 0 ? 1 : config.longBreakInterval;
    if (completedPomodorosAfter > 0 &&
        completedPomodorosAfter % interval == 0) {
      return TimerPhase.longBreak;
    }
    return TimerPhase.shortBreak;
  }

  /// 当前阶段走完后，新的累计专注数。
  /// 只有专注阶段会增加计数，休息阶段不变。
  static int completedAfter(TimerPhase current, int completedPomodoros) =>
      current == TimerPhase.focus
          ? completedPomodoros + 1
          : completedPomodoros;
}

/// JSON 值 → int，类型不对返回 null（交给调用方回退默认值）。
/// 不用 `as num?`：那遇到字符串会**抛异常**而不是回退。
int? _asInt(Object? v) => v is num ? v.toInt() : null;

/// JSON 值 → bool，类型不对返回 null
bool? _asBool(Object? v) => v is bool ? v : null;
