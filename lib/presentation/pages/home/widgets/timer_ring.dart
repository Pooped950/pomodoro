import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../widgets/motion_scope.dart';

/// 主界面的环形进度条 —— 整个 App 的主视觉。
///
/// [fraction] 是**剩余**比例（1.0 = 刚满，0.0 = 走完），
/// 所以时间越少，圈越短，符合倒计时的直觉。
class TimerRing extends StatelessWidget {
  const TimerRing({
    super.key,
    required this.fraction,
    required this.timeText,
    required this.phaseLabel,
    required this.color,
    required this.size,
    this.strokeWidth = 14,
    this.animate = true,
  });

  final double fraction;
  final String timeText;
  final String phaseLabel;
  final Color color;
  final double size;
  final double strokeWidth;

  /// 暂停时关闭动画，避免数字"缓慢漂移"的怪异观感
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // 光晕：呼应 HyperOS 4「柔光玻璃」的灵动光效
          // —— 材质会感知交互行为并用光效响应，环形进度同理
          Container(
            width: size * 0.72,
            height: size * 0.72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withAlpha(12),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: color.withAlpha(72),
                  blurRadius: size * 0.16,
                  spreadRadius: 0,
                ),
              ],
            ),
          ),

          // 环本体
          //
          // 时长走动效规范。注意这里的动画**每秒会被重新触发一次**
          // （fraction 随时钟变），所以时长必须明显小于 1 秒 ——
          // 否则上一段还没演完就被下一段打断，看起来是"追不上的慢半拍"。
          // 280ms 基准、悠长档也才 420ms，留足了余量。
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: fraction, end: fraction),
            duration: animate
                ? MotionScope.of(context).standard
                : Duration.zero,
            curve: Curves.easeOut,
            builder: (BuildContext context, double value, Widget? child) {
              return CustomPaint(
                size: Size.square(size),
                painter: _RingPainter(
                  fraction: value,
                  color: color,
                  trackColor: scheme.onSurface.withAlpha(20),
                  strokeWidth: strokeWidth,
                ),
              );
            },
          ),

          // 中心文字
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: size * 0.66),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    timeText,
                    maxLines: 1,
                    style: text.displayLarge?.copyWith(
                      color: scheme.onSurface,
                      fontFeatures: const <ui.FontFeature>[
                        // 等宽数字：避免倒计时跳动时文字宽度变化
                        ui.FontFeature('tnum'),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                phaseLabel,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurface.withAlpha(140),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double fraction;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (size.shortestSide - strokeWidth) / 2;
    if (radius <= 0) return;

    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    // 底圈
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = trackColor,
    );

    final double f = fraction.clamp(0.0, 1.0);
    if (f <= 0.0005) return;

    // 从 12 点方向开始，顺时针画 f 圈
    const double start = -math.pi / 2;
    final double sweep = math.pi * 2 * f;

    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.sweep(
          center,
          <Color>[color.withAlpha(140), color],
          null,
          TileMode.clamp,
          start,
          start + math.max(sweep, 0.01),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
