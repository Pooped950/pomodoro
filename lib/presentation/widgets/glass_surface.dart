import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// 液态玻璃容器 —— 对齐 iOS 26 Liquid Glass 的观感。
///
/// ## 从「柔光玻璃」升级到「液态玻璃」加了什么
///
/// 1. **方向性镜面高光**：边缘不再是均匀一圈白边，而是**左上最亮、右下近透明**
///    （见 [_GlassRimPainter]，用渐变描边实现）。这是"实体材料感"的主要来源 ——
///    均匀白边看起来像塑料片，有光照方向的边缘才像玻璃。
/// 2. **厚度暗示**：内阴影（玻璃内壁的暗部）+ 略粗的高光边缘 + 外投影，
///    让玻璃"浮"在背景上，而不是贴在背景里。
/// 3. **活力色叠加**：Flutter 3.47 的 BackdropFilter 滤镜链放不进颜色矩阵，
///    做不了真正的饱和度提升（见 [_glassFilter] 注释），改用一层极淡的主色渐变
///    近似 iOS 那种"透光且鲜艳"的观感。
///
/// ## ⚠️ 没做到的（要说清楚，别让人以为这就是 iOS 原版）
///
/// **真实折射** —— 玻璃边缘把背景"掰弯"的透镜效果 —— **没有实现**。
/// 那需要对背景纹理做逐像素位移，只能用 `ui.ImageFilter.shader` 配自定义
/// 片元着色器。当前是"模糊 + 方向性高光 + 厚度"的近似：
/// 观感接近，但不是逐像素折射。
///
/// ## 使用前提（最容易搞错的一点）
///
/// `BackdropFilter` 模糊的是它**背后**的内容。所以：
///   - 只有容器真的盖在内容上（例如滚动列表上方的悬浮导航条）才值得用玻璃；
///     盖在纯色块上的容器请直接用 `elevatedSurface()` —— 白付一次高斯模糊的开销，
///     观感还更差
///   - 页面背景必须铺环境色（见 `AmbientBackground`），否则玻璃折射出来还是纯色，
///     观感上等于没有玻璃
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = AppRadius.card,
    this.padding,
    this.blur,
    this.tint,
    this.rim = true,
    this.specular = true,
  });

  final Widget child;

  /// 圆角半径
  final double radius;

  final EdgeInsetsGeometry? padding;

  /// 模糊半径，默认取 [GlassTokens.blur]
  final double? blur;

  /// 玻璃底色，默认取主题 surface
  final Color? tint;

  /// 是否绘制方向性边缘高光
  final bool rim;

  /// 是否绘制顶部镜面高光
  final bool specular;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isDark = scheme.brightness == Brightness.dark;

    // 自适应通透度：浅色环境更实、深色环境更透，保证文字始终可读
    final double opacity =
        isDark ? GlassTokens.opacityDark : GlassTokens.opacityLight;
    final Color base =
        (tint ?? scheme.surface).withAlpha((opacity * 255).round());

    // 方向性高光：左上亮 → 右下近透明
    final double rimTop = isDark
        ? GlassTokens.rimTopAlpha * 0.45
        : GlassTokens.rimTopAlpha;
    final Color rimTopColor = Colors.white.withAlpha((rimTop * 255).round());
    final Color rimBottomColor = Colors.white
        .withAlpha((GlassTokens.rimBottomAlpha * 255).round());

    final double specAlpha = GlassTokens.specularAlpha * (isDark ? 0.55 : 1.0);
    final Color specColor = Colors.white.withAlpha((specAlpha * 255).round());

    // 活力色叠加强度
    final double vibAlpha = isDark
        ? GlassTokens.vibrancyAlphaDark
        : GlassTokens.vibrancyAlphaLight;

    final BorderRadius borderRadius = BorderRadius.circular(radius);
    final double sigma = blur ?? GlassTokens.blur;

    return DecoratedBox(
      // 外投影：让玻璃"浮"在背景上，拉开层次
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withAlpha(
              (GlassTokens.outerShadowAlpha * (isDark ? 170 : 255)).round(),
            ),
            blurRadius: GlassTokens.outerShadowBlur,
            offset: const Offset(0, GlassTokens.outerShadowOffsetY),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: _glassFilter(sigma),
          child: Stack(
            children: <Widget>[
              // 玻璃底色
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: borderRadius,
                  ),
                ),
              ),

              // 活力色：极淡的主色渐变，近似"透光且鲜艳"
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          scheme.primary.withAlpha((vibAlpha * 255).round()),
                          scheme.tertiary
                              .withAlpha((vibAlpha * 0.5 * 255).round()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 内阴影：玻璃内壁的暗部 → 厚度感
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withAlpha(
                            (GlassTokens.innerShadowAlpha * 255).round(),
                          ),
                          blurRadius: 12,
                          spreadRadius: -2,
                          offset: const Offset(0, 4),
                          blurStyle: BlurStyle.inner,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 顶部镜面高光：从顶部往下 45% 处淡出
              if (specular)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: borderRadius,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[specColor, specColor.withAlpha(0)],
                          stops: const <double>[0.0, 0.45],
                        ),
                      ),
                    ),
                  ),
                ),

              // 方向性边缘高光
              if (rim)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: GlassRimPainter(
                        radius: radius,
                        width: GlassTokens.rimWidth,
                        topColor: rimTopColor,
                        bottomColor: rimBottomColor,
                      ),
                    ),
                  ),
                ),

              // 内容
              Padding(
                padding: padding ?? EdgeInsets.zero,
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 方向性边缘高光：用**渐变描边**画圆角矩形，左上亮、右下暗。
///
/// 为什么不用 `Border.all`：Flutter 的 `Border` 不支持渐变颜色，
/// 而"均匀白边"正是塑料片观感的来源。
///
/// 公开（非私有）是因为液态玻璃主按钮也要用同一套边缘处理 ——
/// 边缘高光的方向和强度必须全 App 一致，否则按钮和卡片会像两种材质。
class GlassRimPainter extends CustomPainter {
  const GlassRimPainter({
    required this.radius,
    required this.width,
    required this.topColor,
    required this.bottomColor,
  });

  final double radius;
  final double width;
  final Color topColor;
  final Color bottomColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    // 内缩半个描边宽度，让描边完整落在容器内
    // （否则外半圈会被 ClipRRect 切掉，边缘看起来缺一块）
    final RRect rrect = RRect.fromRectAndRadius(
      rect.deflate(width / 2),
      Radius.circular(radius),
    );
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[topColor, bottomColor],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(GlassRimPainter old) =>
      old.radius != radius ||
      old.width != width ||
      old.topColor != topColor ||
      old.bottomColor != bottomColor;
}

/// 玻璃滤镜：单句高斯模糊。
///
/// 设计上还想在模糊上叠「饱和度 + 亮度」颜色矩阵（防透出发灰），但
/// Flutter 3.47 的 dart:ui ImageFilter 只有 blur/dilate/erode/matrix/compose/shader
/// 五种工厂，**没有 colorFilter** —— 4x5 颜色矩阵进不了 BackdropFilter 滤镜链；
/// 而 ImageFilter.matrix 要的是 4x4 几何矩阵（16 个元素），塞 20 元素的颜色矩阵
/// 会抛 "matrix4 must have 16 entries"（2026-10-05 实测，悬浮导航条曾因此构建失败）。
///
/// 防发灰改由玻璃底色 tint、活力色叠加与顶部镜面高光补偿；
/// GlassTokens.saturation / brightness 两参数暂未生效。
///
/// 真实折射（透镜位移）需要 `ui.ImageFilter.shader` 配自定义片元着色器，当前未实现。
ui.ImageFilter _glassFilter(double sigma) =>
    ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
