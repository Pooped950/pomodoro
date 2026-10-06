import 'package:flutter/material.dart';

/// 预设背景色卡。
///
/// ## 为什么放在表现层而不是领域层
///
/// 领域层的 `BackgroundSettings` 只存一个 `presetId` 字符串，
/// **不含任何颜色值** —— "某个预设长什么样"是纯视觉问题，
/// 改配色不该牵动数据模型（也不该让领域层 import Flutter）。
///
/// ## 为什么用"几个彩色光斑"而不是"一整块渐变"
///
/// 因为玻璃要"看得见"，前提是**背后有东西可折射**（见 `AmbientBackground`
/// 的注释）。一整块均匀渐变折射出来还是均匀的，玻璃盖上去几乎没有层次；
/// 而几个大半径光斑叠出来有明暗过渡，玻璃的边缘高光和模糊才有东西可抓。
/// 这也是 HyperOS「柔光玻璃」的做法。
///
/// ## 颜色怎么选的
///
/// 一律选中**中等饱和度**的色相，不选纯色也不选深色：
///   - 底色始终是主题的 surface（浅色主题是浅色、深色主题是深色），
///     所以同一套光斑在两种主题下都成立
///   - 太饱和会盖掉界面内容、太灰又看不出换过背景
@immutable
class BackgroundPreset {
  const BackgroundPreset({
    required this.id,
    required this.name,
    required this.colors,
    this.strengthScale = 1.0,
  });

  final String id;

  /// 色卡上显示的名字
  final String name;

  /// 光斑用色（2~3 个）
  final List<Color> colors;

  /// 强度缩放。深色系（如「午夜」）要压低一点，否则在深色主题下会糊成一片
  final double strengthScale;
}

/// 全部预设。**顺序就是设置页里的显示顺序**。
const List<BackgroundPreset> kBackgroundPresets = <BackgroundPreset>[
  BackgroundPreset(
    id: 'sunrise',
    name: '暖阳',
    colors: <Color>[
      Color(0xFFFFB07C),
      Color(0xFFFF8FA3),
      Color(0xFFFFD98A),
    ],
  ),
  BackgroundPreset(
    id: 'ocean',
    name: '海盐',
    colors: <Color>[
      Color(0xFF6EC6FF),
      Color(0xFF4FC3F7),
      Color(0xFF80DEEA),
    ],
  ),
  BackgroundPreset(
    id: 'forest',
    name: '苔原',
    colors: <Color>[
      Color(0xFF8BC34A),
      Color(0xFF4DB6AC),
      Color(0xFFAED581),
    ],
  ),
  BackgroundPreset(
    id: 'dusk',
    name: '暮紫',
    colors: <Color>[
      Color(0xFF9C6BFF),
      Color(0xFFE17BD8),
      Color(0xFF6B7BFF),
    ],
  ),
  BackgroundPreset(
    id: 'sakura',
    name: '樱粉',
    colors: <Color>[
      Color(0xFFFF9EC7),
      Color(0xFFFFC2D9),
      Color(0xFFB39DFF),
    ],
  ),
  BackgroundPreset(
    id: 'sand',
    name: '沙丘',
    colors: <Color>[
      Color(0xFFD7B98E),
      Color(0xFFE8C9A0),
      Color(0xFFC9A227),
    ],
    strengthScale: 0.9,
  ),
  BackgroundPreset(
    id: 'midnight',
    name: '午夜',
    colors: <Color>[
      Color(0xFF3D5AFE),
      Color(0xFF7C4DFF),
      Color(0xFF00B8D4),
    ],
    // 深色系压低强度：在深色主题下这几块颜色本身就很重，
    // 不压的话会把整屏糊成一片深蓝，界面内容全被吃掉
    strengthScale: 0.85,
  ),
];

/// 按 id 取预设。找不到（老版本数据 / 手工改过库）回退到第一个，
/// **不返回 null** —— 背景画不出来比"配色回退"严重得多。
BackgroundPreset presetById(String id) {
  for (final BackgroundPreset p in kBackgroundPresets) {
    if (p.id == id) return p;
  }
  return kBackgroundPresets.first;
}

/// 色卡小圆点上显示的渐变色（两色即可，三点太小看不出第三个）
List<Color> presetSwatchColors(BackgroundPreset preset) {
  if (preset.colors.length >= 2) {
    return <Color>[preset.colors[0], preset.colors[1]];
  }
  return <Color>[preset.colors.first, preset.colors.first];
}
