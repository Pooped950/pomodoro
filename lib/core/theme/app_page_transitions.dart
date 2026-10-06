import 'package:flutter/material.dart';

import 'motion_tokens.dart';

/// 二级页面的**统一转场**。
///
/// ## 解决什么问题
///
/// 用户的原话：「点击后台保活设置以后跳出来的界面太快了，我要你做好动画衔接
/// 效果补帧」。
///
/// 原来用的是 `MaterialPageRoute` 的默认转场（Android 上是 Zoom 缩放淡入），
/// 300ms 左右、而且**只有新页面在动** —— 底下的页面纹丝不动。
/// 看起来就像"啪"地换了一张图，没有"从哪来"的空间感。
///
/// 现在改成两层同时动：
///   1. **新页面**从右侧滑入 + 淡入（有明确的来向）
///   2. **底下的页面**轻微左移 + 略微变暗（被"推走"的层次感）
///
/// 第 2 层是关键 —— 只有新页面动的话仍然像贴图；两层一起动才有"翻页"的实体感。
///
/// ## 为什么曲线是"极快起步、极长收尾"
///
/// [MotionTokens.emphasized] 的 Cubic(0.2, 0, 0, 1)：前 20% 时间走完约一半路程，
/// 剩下 80% 时间都在慢慢收尾。视觉上就是"轻盈地滑进来然后稳稳停住"，
/// 而不是匀速平移到位 —— 后者即使时长加长也只会显得"慢"，不会显得"顺"。
Widget buildAppPageTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  // 进入：本次路由自己的动画
  final Animation<double> enter = CurvedAnimation(
    parent: animation,
    curve: MotionTokens.emphasized,
    reverseCurve: MotionTokens.emphasizedIn,
  );

  // 让位：被上面新路由压住时，本页的退让动画
  final Animation<double> yield_ = CurvedAnimation(
    parent: secondaryAnimation,
    curve: MotionTokens.emphasized,
    reverseCurve: MotionTokens.emphasizedIn,
  );

  return SlideTransition(
    // 让位：向左挪一点点（5% 宽度）。挪多了会露馅，挪少了看不出层次。
    // ⚠️ begin/end 对应 secondaryAnimation 的两个状态：
    //   0 = 本页是顶层、无遮挡（常态！）→ 必须是 Offset.zero；
    //   1 = 被新页盖住 → 才左移让位。
    // 2026-10-06 回归教训：这里曾把两个状态写反（常态左移 5% ≈ 20dp），
    // 导致全 App 每一页整体左偏、屏幕右侧露出一条黑边 —— 因为位移量
    // 恰好等于"宽度 × 5%"，在不同屏宽的设备上都表现为 ~20dp，极具迷惑性。
    position: Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.05, 0),
    ).animate(yield_),
    child: FadeTransition(
      // 让位时略微变暗，进一步拉开前后层次（不遮太多，否则回来看不清）
      opacity: Tween<double>(begin: 1, end: 0.86).animate(yield_),
      child: SlideTransition(
        // 进入：从右侧 22% 宽度处滑进来。
        // 不用整屏滑 —— 整屏滑在 420ms 下会显得"跑得很远"，22% 足够表达方向
        position: Tween<Offset>(
          begin: const Offset(0.22, 0),
          end: Offset.zero,
        ).animate(enter),
        child: FadeTransition(
          // 淡入的起点不是 0：完全透明地滑进来会有一瞬间"什么都没有"，
          // 从 0.4 起步能保证整段动画里画面始终是"有东西"的
          opacity: Tween<double>(begin: 0.4, end: 1).animate(enter),
          child: child,
        ),
      ),
    ),
  );
}

/// 把这个转场注册到主题里，**所有 `MaterialPageRoute` 都会自动用上**。
///
/// 为什么要走主题而不是在每个 push 的地方写：
///   - 底下那一页的"让位"动画是由**它自己的路由**驱动的，
///     而 `AppShell` 所在的路由是 `MaterialApp.home` 自动建的，
///     我们没法在那次 push 里给它定制动画。只有主题能覆盖到它。
///   - 以后新增页面时不用记得"要套转场"，默认就是对的。
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      buildAppPageTransition(context, animation, secondaryAnimation, child);
}
