import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/motion_tokens.dart';
import 'motion_scope.dart';

/// 可按压容器 —— 按下时**底色渐显 + 轻微缩小**，松手弹回。
///
/// ## 为什么不直接用 `InkWell`
///
/// `InkWell` 的水波纹是 Android 的语言（从触点扩散的圆形涟漪），
/// 和这个 App 的玻璃材质放在一起很出戏 —— 玻璃上的涟漪看起来像
/// 一层贴在玻璃表面的水膜，而不是"玻璃被按下去"。
///
/// 所以统一改成：**整块底色渐显 + 轻微缩小 + 一次轻触感**。
/// 这是"实体材料"该有的反馈：按下去，材料受压。
///
/// ## 时长
///
/// 按压反馈必须**短**（[Motion.press]，基准 140ms）—— 它是对手指的
/// 直接响应，长了会觉得"点了没反应"。所以这个时长不跟着用户的
/// 动效节奏倍率放大太多（见 [Motion.press] 的说明）。
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 1.0,
    this.highlightColor,
    this.borderRadius,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 按下时的缩放。1.0 = 不缩放。
  ///
  /// 整行宽的列表项**建议保持 1.0** —— 缩放会让两侧露出空隙，
  /// 看起来像"这行被挤窄了"而不是"被按下了"。缩放留给按钮类元素。
  final double scale;

  /// 按下时渐显的底色。null = 只要缩放，不要底色。
  final Color? highlightColor;

  /// 高亮底色的圆角。不传则铺满整个矩形（列表行用这个）。
  final BorderRadius? borderRadius;

  /// 是否触发一次轻触感（"点到了"的触感反馈）
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
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
    final bool interactive = widget.onTap != null || widget.onLongPress != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: interactive ? (TapDownDetails _) => _setPressed(true) : null,
      onTapUp: interactive ? (TapUpDetails _) => _setPressed(false) : null,
      onTapCancel: interactive ? () => _setPressed(false) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _press,
        child: widget.child,
        builder: (BuildContext context, Widget? child) {
          Widget content = child!;

          final Color? highlight = widget.highlightColor;
          if (highlight != null) {
            content = Stack(
              children: <Widget>[
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        // 从透明渐变到高亮色：按下是"渗出来"的，不是硬切
                        color: Color.lerp(
                          Colors.transparent,
                          highlight,
                          _press.value,
                        ),
                        borderRadius: widget.borderRadius,
                      ),
                    ),
                  ),
                ),
                content,
              ],
            );
          }

          if (widget.scale == 1.0) return content;
          return Transform.scale(
            scale: 1 - (1 - widget.scale) * _press.value,
            child: content,
          );
        },
      ),
    );
  }
}
