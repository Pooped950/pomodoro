import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/motion_tokens.dart';
import 'motion_scope.dart';

/// 入场动画：**淡入 + 从下方轻轻推上来**，可按 [index] 逐项错开。
///
/// ## 为什么做成组件
///
/// 页面里"一块内容浮上来"的需求到处都是（统计卡片、保活页的每一段、
/// 任务列表的行）。每个地方手写一遍 AnimationController 既啰嗦又容易不一致，
/// 所以统一成一个组件 —— 时长和错开间隔都从 `MotionScope` 取，
/// 用户在设置里调"动效节奏"，这里自动跟着变。
///
/// ## 为什么用 `didChangeDependencies` 而不是 `initState`
///
/// 时长要从 `MotionScope`（InheritedWidget）取，而 `initState` 阶段
/// **不允许**查 InheritedWidget。`didChangeDependencies` 是第一个能安全取到的时机，
/// 所以动画在那里启动。
///
/// ## 为什么不直接用 `AnimatedOpacity` + `AnimatedSlide`
///
/// 隐式动画需要一个"从旧值变到新值"的触发过程，而这个组件的语义是
/// "挂载时演一次入场"。用显式 controller 更直接，也能精确控制错开延迟。
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.offsetY = 18,
    this.enabled = true,
  });

  final Widget child;

  /// 列表中的序号，用来算错开延迟（第 n 项晚 n 步出发）
  final int index;

  /// 起始位置相对最终位置向下偏移多少逻辑像素
  final double offsetY;

  /// false = 不做动画，直接显示最终态（用于不需要入场效果的地方）
  final bool enabled;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionTokens.standard,
  );

  Timer? _delayTimer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (!widget.enabled) {
      _controller.value = 1;
      return;
    }

    final Motion motion = MotionScope.of(context);
    _controller.duration = motion.standard;

    final Duration delay = motion.staggerDelay(widget.index);
    if (delay <= Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final Animation<double> curved = CurvedAnimation(
      parent: _controller,
      curve: MotionTokens.emphasized,
    );

    return AnimatedBuilder(
      animation: curved,
      // child 只构建一次，动画每帧只重算变换 —— 重建范围最小
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        return Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(0, widget.offsetY * (1 - curved.value)),
            child: child,
          ),
        );
      },
    );
  }
}
