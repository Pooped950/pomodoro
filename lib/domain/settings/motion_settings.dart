import 'package:meta/meta.dart';

/// 动效节奏设置 —— 一个作用到**全局所有动画**的时长倍率。
///
/// ## 为什么做成一个倍率而不是逐个动画去调
///
/// 用户的原话是「整体 app 里所有的动画都不要求快，要求丝滑补帧高级」。
/// 逐个动画调时长的话，以后想整体再快一点/慢一点就要改几十处、还容易漏。
/// 做成一个倍率后：所有动画的基准时长都在 `MotionTokens` 里，
/// 实际时长 = 基准 × [scale]。用户在设置里拖一下滑动条，全 App 一起变。
///
/// ## 倍率的合法性由构造入口保证
///
/// 公开的构造是 `factory MotionSettings(...)`，**倍率在那里就被夹好**，
/// 所以任何一个 `MotionSettings` 实例都是合法的（scale 恒在区间内、恒 > 0）。
/// 私有的 `._()` 只服务于常量 [defaults]。
///
/// 为什么要这么较真：倍率一旦变成 0 或负数，所有动画会**瞬间完成** ——
/// 用户看到的现象是"动效全坏了"，而根本联想不到是设置项的问题。
/// 与其在几十个使用点各判一次，不如让非法实例根本造不出来。
///
/// ## 领域层保持纯净
///
/// 这个类**不 import Flutter**（除 `meta` 的 `@immutable`），
/// 所以"倍率怎么夹取、脏数据怎么回退"这些规则能在宿主机直接单测。
/// 时长与曲线的实际换算在表现层的 `Motion`（见 `widgets/motion_scope.dart`）。
@immutable
class MotionSettings {
  /// 唯一公开入口。倍率在这里夹取，实例永远合法。
  factory MotionSettings({double scale = defaultScale}) =>
      MotionSettings._(clampScale(scale));

  const MotionSettings._(this.scale);

  /// 默认倍率 —— 对应「从容」档。用户要求默认就是这一档。
  static const double defaultScale = 1.0;

  /// 滑动条下限（「轻盈」端）
  static const double minScale = 0.65;

  /// 滑动条上限（「悠长」端）
  static const double maxScale = 1.50;

  /// 默认档实例。`const`，可直接用在 const 上下文。
  static const MotionSettings defaults = MotionSettings._(defaultScale);

  /// 时长倍率。1.0 = 基准时长；< 1 更快；> 1 更慢。恒在 [minScale, maxScale] 内。
  final double scale;

  /// 夹取到合法区间。
  static double clampScale(double raw) {
    if (raw.isNaN) return defaultScale;
    if (raw < minScale) return minScale;
    if (raw > maxScale) return maxScale;
    return raw;
  }

  /// 把基准时长换算成实际时长。
  Duration of(Duration base) => base * scale;

  /// 节奏档位名 —— 设置页滑动条上方显示，让用户知道自己拖到了哪一档。
  String get label {
    if (scale < 0.85) return '轻盈';
    if (scale < 1.15) return '从容';
    if (scale < 1.35) return '舒缓';
    return '悠长';
  }

  /// 一句话解释当前档位的手感，避免用户只看到"轻盈/悠长"却不知道差在哪
  String get hint => switch (label) {
        '轻盈' => '接近系统原生的干脆手感',
        '从容' => '能看清每一帧，又不拖沓',
        '舒缓' => '过程更明显，节奏更慢',
        _ => '最有仪式感，但连续操作会显得慢',
      };

  /// 这个倍率是否就是默认档（用于"用户在读取完成前已经拖过就不覆盖"的判断）
  bool get isDefault => scale == defaultScale;

  MotionSettings copyWith({double? scale}) =>
      MotionSettings(scale: scale ?? this.scale);

  Map<String, Object?> toJson() => <String, Object?>{'scale': scale};

  /// 从持久化 JSON 还原。
  ///
  /// **缺字段 / 类型不对一律回退默认值，绝不读成 0** ——
  /// 倍率读成 0 的话所有动画瞬间完成，用户会觉得"动效全坏了"。
  /// 也不用 `as double`（JSON 里的整数会解析成 int，强转会抛异常）。
  static MotionSettings fromJson(Map<String, Object?>? json) {
    if (json == null) return defaults;
    final Object? raw = json['scale'];
    if (raw is num) return MotionSettings(scale: raw.toDouble());
    return defaults;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MotionSettings && other.scale == scale;

  @override
  int get hashCode => scale.hashCode;

  @override
  String toString() => 'MotionSettings(scale: $scale, label: $label)';
}
