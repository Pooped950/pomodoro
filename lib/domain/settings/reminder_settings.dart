import 'package:meta/meta.dart';

/// 到点提醒设置 —— M4 设置页补齐。
///
/// ## 语义（重要）
///
/// **关掉提醒 ≠ 不提醒。** 关掉只是"不响铃不震动"，到点通知照常出现 ——
/// 用户关的通常是"响"，不是"提醒"。所以精确闹钟该排还是排，
/// 只是换一个静默的通知渠道。
///
/// 用「响铃」而不是「提醒」来命名总开关，就是为了让这个语义在界面上不自相矛盾。
@immutable
class ReminderSettings {
  const ReminderSettings({
    this.soundEnabled = true,
    this.vibrateEnabled = true,
  });

  /// 到点是否响铃（总开关）。关掉则铃声与震动一起关，只留通知。
  final bool soundEnabled;

  /// 响铃时是否同时震动。仅在 [soundEnabled] 为 true 时有意义。
  final bool vibrateEnabled;

  /// 实际生效的震动 —— 总开关关掉时强制不震，
  /// 避免出现"总开关关了还在震"这种矛盾状态。
  bool get effectiveVibrate => soundEnabled && vibrateEnabled;

  /// 是否走静默通知渠道
  bool get silent => !soundEnabled;

  Map<String, Object?> toJson() => <String, Object?>{
        'soundEnabled': soundEnabled,
        'vibrateEnabled': vibrateEnabled,
      };

  /// 缺字段 / 类型不对一律回退默认值（与 TimerConfig 同一套容错策略）
  factory ReminderSettings.fromJson(Map<String, Object?> json) {
    const ReminderSettings d = ReminderSettings();
    return ReminderSettings(
      soundEnabled: _asBool(json['soundEnabled']) ?? d.soundEnabled,
      vibrateEnabled: _asBool(json['vibrateEnabled']) ?? d.vibrateEnabled,
    );
  }

  ReminderSettings copyWith({bool? soundEnabled, bool? vibrateEnabled}) =>
      ReminderSettings(
        soundEnabled: soundEnabled ?? this.soundEnabled,
        vibrateEnabled: vibrateEnabled ?? this.vibrateEnabled,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReminderSettings &&
          other.soundEnabled == soundEnabled &&
          other.vibrateEnabled == vibrateEnabled;

  @override
  int get hashCode => Object.hash(soundEnabled, vibrateEnabled);

  @override
  String toString() =>
      'ReminderSettings(响铃: $soundEnabled, 震动: $vibrateEnabled)';
}

bool? _asBool(Object? v) => v is bool ? v : null;
