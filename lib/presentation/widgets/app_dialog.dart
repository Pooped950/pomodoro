import 'package:flutter/material.dart';

import '../../core/theme/motion_tokens.dart';
import 'motion_scope.dart';

/// 统一的对话框弹出方式，**时长走动效规范**。
///
/// ## 为什么不用 `showDialog`
///
/// `showDialog` 的进出场时长写死在 150ms —— 是全 App 最快的动画。
/// 在别的动画都放到 380~420ms 之后，这个 150ms 的对话框会显得
/// "啪"地砸出来，非常突兀（用户要求的是"整体"丝滑，不是只有某一处）。
///
/// 这里用 `showGeneralDialog` 显式指定时长，并加上**轻微回弹**
/// （[MotionTokens.overshoot]）—— 对话框是有实体感的"一块板"，
/// 弹出来时略微冲过头再稳住，比匀速放大自然得多。
///
/// 注意：回弹只给对话框和底部弹层用，**不要用在页面转场上** ——
/// 整屏页面回弹会让人晕。
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final Motion motion = MotionScope.resolve(context);

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    // barrierDismissible 为 true 时必须给 label（无障碍要能读出来）
    barrierLabel: '关闭对话框',
    barrierColor: Colors.black.withValues(alpha: 0.32),
    transitionDuration: motion.dialog,
    pageBuilder: (
      BuildContext _,
      Animation<double> _,
      Animation<double> _,
    ) =>
        Builder(builder: builder),
    transitionBuilder: (
      BuildContext ctx,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    ) {
      final Animation<double> curved = CurvedAnimation(
        parent: animation,
        curve: MotionTokens.overshoot,
        reverseCurve: MotionTokens.emphasizedIn,
      );

      return FadeTransition(
        // 透明度用原始 animation（线性），缩放用带曲线的 ——
        // 让透明度跟得上回弹的节奏，不会出现"已经弹到位了还在淡入"
        opacity: CurvedAnimation(
          parent: animation,
          curve: const Interval(0, 0.6, curve: Curves.easeOut),
        ),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
