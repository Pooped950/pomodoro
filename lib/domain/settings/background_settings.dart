import 'package:meta/meta.dart';

/// 背景类型
enum BackgroundKind {
  /// 跟随主题（内置的环境色光晕）—— 默认
  theme,

  /// 预设色卡
  preset,

  /// 相册照片
  image;

  static BackgroundKind fromName(String? name) {
    for (final BackgroundKind k in BackgroundKind.values) {
      if (k.name == name) return k;
    }
    // 脏数据 / 老版本 → 回退到最安全的那个（主题背景一定画得出来）
    return BackgroundKind.theme;
  }
}

/// 主页背景设置。
///
/// ## 为什么单独一个模型，而不是塞进 `AppThemeMode`
///
/// 主题管的是"深浅色"，背景管的是"主页背后那层画什么"，是两件事：
/// 用户可以"深色主题 + 相册照片"，也可以"浅色主题 + 预设色卡"。
/// 混在一起以后想加"只给统计页换背景"这类需求就没法表达了。
///
/// ## 领域层保持纯净
///
/// 这个类**不 import Flutter**（除 `meta` 的 `@immutable`），
/// 存的是 `presetId` 字符串和图片路径，**不含任何颜色值** ——
/// "某个预设长什么样"是纯视觉问题，放在表现层的 `background_presets.dart`。
/// 这样领域层能在宿主机直接单测，也不会因为改配色而牵动数据模型。
@immutable
class BackgroundSettings {
  const BackgroundSettings({
    this.kind = BackgroundKind.theme,
    this.presetId = defaultPresetId,
    this.imagePath,
    this.dim = defaultDim,
    this.blurred = true,
  });

  /// 默认预设 id（kind 为 preset 且 presetId 无效时用它兜底）
  static const String defaultPresetId = 'sunrise';

  /// 默认暗度
  static const double defaultDim = 0.30;

  static const double minDim = 0.0;
  static const double maxDim = 0.75;

  /// 图片解码上限（像素宽）。相册原图动辄 4000px 宽，
  /// 整张解码进内存要几十 MB，再叠高斯模糊会直接卡住 ——
  /// 所以按"足够覆盖 1200px 宽的屏幕"来限制解码尺寸。
  static const int imageDecodeWidth = 1080;

  final BackgroundKind kind;

  /// [BackgroundKind.preset] 时用哪个预设
  final String presetId;

  /// [BackgroundKind.image] 时的图片路径（已复制到应用私有目录）
  final String? imagePath;

  /// 图片上叠的暗度。0 = 不压暗；越大越暗。
  ///
  /// 为什么需要它：背景图是**用户随便选的**，可能是雪景（很亮）
  /// 也可能是夜景（很暗）。不做压暗的话，白色玻璃和深色文字在亮图上
  /// 会直接看不清。给一个可调暗度，让用户自己找到"好看又看得清"的点。
  final double dim;

  /// 是否对图片做高斯模糊。
  ///
  /// 默认开：模糊过的照片当背景更耐看（细节不抢视线），
  /// 而且玻璃盖上去的层次更明显。但有些照片用户就是想要清晰的，
  /// 所以给个开关。
  final bool blurred;

  /// 图片路径是否可用（选了图片但路径丢了的情况要能识别出来）
  bool get hasUsableImage =>
      kind == BackgroundKind.image &&
      imagePath != null &&
      imagePath!.isNotEmpty;

  /// **实际生效的**类型。
  ///
  /// 关键：用户选了图片、但文件后来没了（被清理 / 换机恢复），
  /// 这时不能画一张白板 —— 要回退到主题背景，界面至少是正常的。
  BackgroundKind get effectiveKind =>
      kind == BackgroundKind.image && !hasUsableImage
          ? BackgroundKind.theme
          : kind;

  static double clampDim(double raw) {
    if (raw.isNaN) return defaultDim;
    if (raw < minDim) return minDim;
    if (raw > maxDim) return maxDim;
    return raw;
  }

  BackgroundSettings copyWith({
    BackgroundKind? kind,
    String? presetId,
    String? imagePath,
    bool clearImagePath = false,
    double? dim,
    bool? blurred,
  }) =>
      BackgroundSettings(
        kind: kind ?? this.kind,
        presetId: presetId ?? this.presetId,
        imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
        dim: clampDim(dim ?? this.dim),
        blurred: blurred ?? this.blurred,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'presetId': presetId,
        'imagePath': imagePath,
        'dim': dim,
        'blurred': blurred,
      };

  /// 从持久化 JSON 还原。**任何字段有问题都退回默认值，不抛异常** ——
  /// 背景画不出来会直接让整个主页变成一块空白，比"背景回到默认"严重得多。
  static BackgroundSettings fromJson(Map<String, Object?>? json) {
    if (json == null) return const BackgroundSettings();

    final Object? rawDim = json['dim'];
    final Object? rawPreset = json['presetId'];
    final Object? rawPath = json['imagePath'];
    final Object? rawKind = json['kind'];
    final Object? rawBlurred = json['blurred'];

    return BackgroundSettings(
      // 用 `is String` 判断而不是 `as String?` —— 库里存了数字时
      // 强转会抛 CastError，整个设置读取就崩了
      kind: BackgroundKind.fromName(rawKind is String ? rawKind : null),
      presetId: rawPreset is String && rawPreset.isNotEmpty
          ? rawPreset
          : defaultPresetId,
      imagePath: rawPath is String && rawPath.isNotEmpty ? rawPath : null,
      dim: rawDim is num ? clampDim(rawDim.toDouble()) : defaultDim,
      // 缺字段时按"开"处理：模糊是更好看的默认值
      blurred: rawBlurred is bool ? rawBlurred : true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackgroundSettings &&
          other.kind == kind &&
          other.presetId == presetId &&
          other.imagePath == imagePath &&
          other.dim == dim &&
          other.blurred == blurred;

  @override
  int get hashCode => Object.hash(kind, presetId, imagePath, dim, blurred);

  @override
  String toString() =>
      'BackgroundSettings(${kind.name}, preset: $presetId, image: $imagePath, '
      'dim: $dim, blurred: $blurred)';
}
