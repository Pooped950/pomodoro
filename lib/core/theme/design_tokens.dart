import 'package:flutter/material.dart';

/// 设计令牌 —— 落地自《番茄钟 App 项目方案》5.2 节
///
/// 规则：页面里不要出现魔法数字，所有圆角 / 间距都从这里取。
/// 想统一调整 UI 观感时，只改这个文件。
class AppRadius {
  const AppRadius._();

  /// 大卡片 / 主容器
  static const double card = 28;

  /// 中卡片 / 列表项
  static const double cardMedium = 20;

  /// 按钮
  static const double button = 24;

  /// 小标签 / 输入框
  static const double chip = 12;

  /// 完全圆形（药丸）
  static const double pill = 999;
}

class AppSpacing {
  const AppSpacing._();

  /// 页面左右边距
  static const double page = 20;

  /// 模块之间
  static const double section = 24;

  /// 模块内元素之间
  static const double item = 16;

  /// 紧密元素之间
  static const double tight = 8;
}

/// 内容区最大宽度。
/// 目标机是 6.9 英寸大屏，不限宽会让元素被拉得很散（方案 5.4 节）。
const double kMaxContentWidth = 480;

/// 主页环形进度条直径占可用宽度的比例
const double kRingWidthRatio = 0.72;

/// 主按钮高度
const double kPrimaryButtonHeight = 56;

/// 底部悬浮导航条的总占位高度（含外边距 + 手势条安全区）。
/// 页面底部必须预留这么多空间，否则内容会被导航条盖住。
const double kBottomNavSpace = 100;

/// 柔光玻璃材质参数 —— HyperOS 4 的核心材质。
///
/// HyperOS 4 把系统材质从"毛玻璃"升级为「柔光玻璃」，三个特性：
///   1. 感知环境颜色 —— 底色跟随主题/动态取色
///   2. 自适应通透度 —— 根据明暗环境自动调整透明度，保证文字可读
///   3. 感知交互行为 —— 边缘高光，按下时有灵动光效
///
/// ⚠️ 一个必须理解的前提：**玻璃只有在"背后有东西"时才看得出来**。
/// 纯白页面 + 白玻璃 = 观感上等于没有玻璃。所以：
///   - 应用背景必须有环境色这层光晕，否则玻璃没有东西可折射
///   - 玻璃容器必须真的盖在内容上，不能盖在纯色块上
class GlassTokens {
  const GlassTokens._();

  /// 背景模糊半径。越大越"糊"，玻璃感越强，性能开销也越大。
  static const double blur = 30;

  /// 浅色环境下的表面不透明度（越透，玻璃感越强，但文字越难读）
  static const double opacityLight = 0.55;

  /// 深色环境下的表面不透明度
  static const double opacityDark = 0.45;

  /// 饱和度提升：让透出来的颜色更"活"
  /// ⚠️ 2026-10-05：Flutter 3.47 的 BackdropFilter 滤镜链放不进颜色矩阵
  /// （无 ImageFilter.colorFilter 工厂），此参数暂未生效，留作备用。
  static const double saturation = 1.8;

  /// 亮度提升：让玻璃看起来是"被照亮的"（同 saturation，暂未生效）
  static const double brightness = 1.08;

  /// 边缘高光宽度。1.6 而不是 1.0 —— 略粗的高光能做出"玻璃有厚度"的暗示。
  static const double rimWidth = 1.6;

  /// 边缘高光强度（浅色环境）—— 已由 [rimTopAlpha]/[rimBottomAlpha] 的
  /// 方向性渐变取代，保留仅供降级路径使用。
  static const double rimAlphaLight = 0.9;

  /// 边缘高光强度（深色环境）
  static const double rimAlphaDark = 0.25;

  /// 顶部镜面高光强度 —— 玻璃"液体感"的主要来源
  static const double specularAlpha = 0.55;

  // ------------------------------------------------------------------
  // 液态玻璃（对齐 iOS 26 Liquid Glass 观感）追加参数
  // ------------------------------------------------------------------

  /// 边缘高光的**方向性**：左上最亮、右下几乎透明。
  ///
  /// 这是让玻璃看起来像"实体材料"而不是"模糊矩形"的关键 ——
  /// iOS 液态玻璃的镜面高光有明确光照方向，不是均匀一圈。
  static const double rimTopAlpha = 0.80;

  /// 右下方向的边缘高光（接近透明，保留一点点避免右下角"断掉"）
  static const double rimBottomAlpha = 0.04;

  /// 内阴影强度 —— 玻璃内壁的暗部，进一步强化厚度
  static const double innerShadowAlpha = 0.14;

  /// 外投影：让玻璃"浮"在背景上，拉开层次
  static const double outerShadowAlpha = 0.16;
  static const double outerShadowBlur = 22;
  static const double outerShadowOffsetY = 8;

  /// 玻璃内部的"活力色"叠加强度。
  ///
  /// Flutter 3.47 的 BackdropFilter 滤镜链放不进颜色矩阵（见 [saturation] 注释），
  /// 无法对透出来的背景做饱和度提升。这里改用一层极淡的主色渐变来近似
  /// iOS 液态玻璃那种"透光且鲜艳"的观感。
  static const double vibrancyAlphaLight = 0.10;
  static const double vibrancyAlphaDark = 0.14;

  /// 环境色强度（浅色模式）。0 = 纯色背景，1 = 明显的彩色氛围。
  /// 「柔光玻璃」的核心是"感知环境颜色"，背景太平玻璃就没有东西可折射。
  /// ⚠️ 初版单档 0.9 实测把整屏染成主色（2026-10-05 模拟器截图核实），已压档。
  static const double ambientStrengthLight = 0.42;

  /// 环境色强度（深色模式）。深色下光晕更收敛，让深浅模式拉开观感。
  static const double ambientStrengthDark = 0.30;

  /// **预设色卡的强度加成**（相对 [ambientStrengthLight]/[ambientStrengthDark]）。
  ///
  /// 为什么预设要单独放大：
  ///   - **主题背景**是"氛围"，要克制、不能抢内容 → 0.42/0.30 是刻意压低的
  ///   - **预设色卡是用户主动选的** —— 选完看不出变化，等于这个功能不存在
  ///
  /// 2026-10-06 模拟器实测踩到：预设「午夜」和主题背景的**整图平均色只差 2/255**
  /// （`#DEDFEB` → `#DEE0ED`），肉眼基本看不出。加上这个 1.9 倍后
  /// 光斑峰值 alpha 从 ~0.12 提到 ~0.27，才是"换了个背景"该有的量级。
  static const double presetStrengthBoost = 1.9;
}

/// 得到"抬升表面"的颜色：在背景色上叠一层极淡的前景色。
///
/// 用途：卡片、底部导航条这类需要和页面背景区分开、但又不能太抢眼的容器。
/// 好处是深色 / 浅色主题下都自动成立，不需要写两套颜色。
Color elevatedSurface(ColorScheme scheme, [double level = 0.04]) =>
    Color.alphaBlend(scheme.onSurface.withValues(alpha: level), scheme.surface);

/// 液态玻璃**主按钮**的参数。
///
/// 单独一组而不是复用 [GlassTokens]：主按钮和卡片玻璃的目标不一样 ——
///   - 卡片玻璃要"透"，让人看出背后有内容
///   - 主按钮是**视觉焦点**，要既看得出是玻璃、又必须保证文字压得住
///
/// 所以主按钮的模糊更大（糊得明显才像玻璃）、底色更实（保证对比度），
/// 另外多一层**强调色外发光** —— 主操作必须"亮"起来才像能点的东西。
class GlassButtonTokens {
  const GlassButtonTokens._();

  /// 背景模糊半径。比卡片玻璃（[GlassTokens.blur] = 30）略小，
  /// 因为按钮面积小、底色更实，模糊太大反而看不出层次。
  static const double blur = 22;

  /// 底色不透明度：**顶端更透、底端更实**。
  ///
  /// 这个上下差异是刻意的：顶端露出模糊的背景（"是玻璃"的证据），
  /// 底端偏实（文字所在的中部区域对比度才稳）。
  /// 均匀透明的话，要么整块糊成一片、要么文字飘在花色背景上读不清。
  static const double tintTopAlpha = 0.58;
  static const double tintBottomAlpha = 0.88;

  /// 顶部镜面高光（玻璃"液体感"的来源）
  static const double specularAlpha = 0.30;

  /// 方向性边缘高光：左上亮、右下弱
  static const double rimTopAlpha = 0.85;
  static const double rimBottomAlpha = 0.12;
  static const double rimWidth = 1.4;

  /// 强调色外发光 —— 主按钮"亮起来"的关键
  static const double glowAlpha = 0.32;
  static const double glowBlur = 26;
  static const double glowOffsetY = 9;

  /// 按下时的缩放。0.972 是"按下去一点"的量级：
  /// 再小（比如 0.94）会像整块按钮被挤扁，很廉价。
  static const double pressedScale = 0.972;

  /// 按下时镜面高光与外发光的增强倍数 —— 手感上"被点亮"
  static const double pressedBoost = 0.55;
}
