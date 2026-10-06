import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/theme/motion_tokens.dart';
import 'glass_surface.dart';
import 'motion_scope.dart';

/// 液态玻璃主按钮 —— 计时页的主操作（开始专注 / 暂停 / 继续）。
///
/// ## 为什么要自己写，不用 `FilledButton`
///
/// 用户的原话是「暂停/继续按钮没有做出高斯模糊液态玻璃效果」。
/// 原来的 `FilledButton` 是一块**纯色**，和整个 App 的玻璃语言脱节 ——
/// 背景是流动的环境色光晕，主按钮却是块实心色，看起来像贴上去的。
///
/// 所以这里自己画：
///   1. **高斯模糊**：真的对背后的环境色做 `BackdropFilter`，
///      而不是"假装玻璃"的浅色填充
///   2. **方向性边缘高光**：复用 [GlassRimPainter]，与卡片玻璃同一套光照方向
///      （左上亮 → 右下弱），保证按钮和卡片像同一种材质
///   3. **上下差异化底色**：顶端更透（露出模糊的背景 = "是玻璃"的证据），
///      底端更实（文字所在区域对比度才稳）
///   4. **强调色外发光**：主操作必须"亮"起来才像能点的东西
///   5. **按压反馈**：按下轻微缩小 + 高光与发光增强，松手弹回
///
/// ## 文字对比度
///
/// 强调色在专注/休息阶段是不同颜色（主色 / 第三色 / 第二色），
/// 深浅不一定。所以文字颜色**不能写死白色** —— 要把强调色按"偏实的那一档"
/// 叠到 surface 上估一次明暗，再决定用白字还是黑字。
/// 写死白色的话，浅色主题下的浅色强调色会直接看不清。
class GlassPrimaryButton extends StatefulWidget {
  const GlassPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.accent,
    required this.onPressed,
    this.height = kPrimaryButtonHeight,
    this.radius = AppRadius.button,
  });

  final String label;
  final IconData icon;

  /// 当前阶段的强调色（专注 = 主色，短休息 = 第三色，长休息 = 第二色）
  final Color accent;

  final VoidCallback onPressed;
  final double height;
  final double radius;

  @override
  State<GlassPrimaryButton> createState() => _GlassPrimaryButtonState();
}

class _GlassPrimaryButtonState extends State<GlassPrimaryButton>
    with SingleTickerProviderStateMixin {
  /// 0 = 未按下，1 = 完全按下
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: MotionTokens.press,
  );

  bool _depsReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_depsReady) return;
    _depsReady = true;
    // 按压时长跟着全局动效节奏走（但不能太长 —— 见 Motion.press 的说明）
    _press.duration = MotionScope.of(context).press;
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (value) {
      _press.forward();
    } else {
      _press.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color accent = widget.accent;

    // 文字颜色：按"偏实的那一档"底色估明暗。
    // 不用 alpha 更高的 tintTop —— 文字在垂直居中处，那里的底色接近 bottom。
    final Color judged = Color.alphaBlend(
      accent.withValues(alpha: GlassButtonTokens.tintBottomAlpha),
      scheme.surface,
    );
    final Color foreground =
        ThemeData.estimateBrightnessForColor(judged) == Brightness.dark
            ? Colors.white
            : const Color(0xE0000000);

    final BorderRadius radius = BorderRadius.circular(widget.radius);

    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (TapDownDetails _) => _setPressed(true),
        onTapUp: (TapUpDetails _) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onPressed,
        // 高度定在**缩放之外**：按压只改变绘制、不改变布局，
        // 否则按下去时下面的元素会跟着抖一下
        child: SizedBox(
          height: widget.height,
          child: AnimatedBuilder(
            animation: _press,
            // 内容不随按压变化，提到外面只构建一次
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(widget.icon, size: 24, color: foreground),
                const SizedBox(width: 10),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            builder: (BuildContext context, Widget? child) {
              final double t = _press.value;
              final double boost = 1 + GlassButtonTokens.pressedBoost * t;

              return Transform.scale(
                scale: 1 - (1 - GlassButtonTokens.pressedScale) * t,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    // 外发光：主按钮"亮起来"的关键，按下时更亮
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: accent.withValues(
                          alpha: (GlassButtonTokens.glowAlpha * boost)
                              .clamp(0.0, 1.0),
                        ),
                        blurRadius: GlassButtonTokens.glowBlur * boost,
                        offset: const Offset(0, GlassButtonTokens.glowOffsetY),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: radius,
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: GlassButtonTokens.blur,
                        sigmaY: GlassButtonTokens.blur,
                      ),
                      // StackFit.expand + 定高父级：Stack 尺寸是确定的，
                      // 不会出现"无定位子项时取 constraints.biggest 拿到无限高"的崩溃
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          // 1. 上下差异化的强调色底色
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  accent.withValues(
                                    alpha: GlassButtonTokens.tintTopAlpha,
                                  ),
                                  accent.withValues(
                                    alpha: GlassButtonTokens.tintBottomAlpha,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // 2. 顶部镜面高光 —— 玻璃"液体感"的来源
                          IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: <Color>[
                                    Colors.white.withValues(
                                      alpha: (GlassButtonTokens.specularAlpha *
                                              boost)
                                          .clamp(0.0, 1.0),
                                    ),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                  stops: const <double>[0.0, 0.5],
                                ),
                              ),
                            ),
                          ),

                          // 3. 内阴影：玻璃内壁的暗部，做出"厚度"
                          IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: radius,
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: GlassTokens.innerShadowAlpha,
                                    ),
                                    blurRadius: 14,
                                    spreadRadius: -2,
                                    offset: const Offset(0, 5),
                                    blurStyle: BlurStyle.inner,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // 4. 方向性边缘高光（与卡片玻璃同一套光照方向）
                          IgnorePointer(
                            child: CustomPaint(
                              painter: GlassRimPainter(
                                radius: widget.radius,
                                width: GlassButtonTokens.rimWidth,
                                topColor: Colors.white.withValues(
                                  alpha: (GlassButtonTokens.rimTopAlpha * boost)
                                      .clamp(0.0, 1.0),
                                ),
                                bottomColor: Colors.white.withValues(
                                  alpha: GlassButtonTokens.rimBottomAlpha,
                                ),
                              ),
                            ),
                          ),

                          // 5. 内容
                          Center(child: child),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
