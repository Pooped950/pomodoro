import 'package:meta/meta.dart';

/// 上课提醒的**方式** —— 每节课上课前 10 分钟怎么提醒你。
///
/// ## 语义（用户 2026-10-09 定）
///
/// 两个复选框，四种组合，**不需要额外一个总开关**：
///
/// | 震动 | 响铃 | 效果 |
/// |---|---|---|
/// | ☑ | ☑ | 震动 + 闹铃（默认） |
/// | ☑ | ☐ | 只震动 |
/// | ☐ | ☑ | 只响铃 |
/// | ☐ | ☐ | **不提醒**（原生侧把已排的闹钟全取消） |
///
/// ⚠️ 和番茄钟的 [ReminderSettings] **语义不同**，别混用：
/// 那边"关掉"只是静默、通知照出；这边两个都关是**真的不提醒**
/// —— 上课提醒响在教室里，用户要能彻底关掉。
@immutable
class ClassReminderSettings {
  const ClassReminderSettings({this.vibrate = true, this.sound = true});

  /// 是否震动
  final bool vibrate;

  /// 是否响铃
  final bool sound;

  /// 还要不要提醒（两个都关 = 不提醒）
  bool get enabled => vibrate || sound;

  /// 通知渠道：[ClassReminderSettings] 的两个开关映射到三个预建渠道
  /// （Android 8+ 的渠道声音/震动**创建后不可改**，只能预建多个来切换）
  String get channel {
    if (sound && vibrate) return 'pomodoro_class';
    if (sound) return 'pomodoro_class_sound';
    return 'pomodoro_class_vibrate';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'vibrate': vibrate,
        'sound': sound,
      };

  /// 缺字段 / 类型不对一律回退默认值（和 [ReminderSettings] 同一套容错策略）
  factory ClassReminderSettings.fromJson(Map<String, Object?> json) {
    const ClassReminderSettings d = ClassReminderSettings();
    return ClassReminderSettings(
      vibrate: _asBool(json['vibrate']) ?? d.vibrate,
      sound: _asBool(json['sound']) ?? d.sound,
    );
  }

  ClassReminderSettings copyWith({bool? vibrate, bool? sound}) =>
      ClassReminderSettings(
        vibrate: vibrate ?? this.vibrate,
        sound: sound ?? this.sound,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassReminderSettings &&
          other.vibrate == vibrate &&
          other.sound == sound;

  @override
  int get hashCode => Object.hash(vibrate, sound);

  @override
  String toString() => 'ClassReminderSettings(震动: $vibrate, 响铃: $sound)';
}

bool? _asBool(Object? v) => v is bool ? v : null;
