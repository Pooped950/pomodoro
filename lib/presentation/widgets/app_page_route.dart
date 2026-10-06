import 'package:flutter/material.dart';

import '../../core/theme/app_page_transitions.dart';
import 'motion_scope.dart';

/// 推一个二级页面，**转场时长走动效规范**。
///
/// ## 为什么需要它（而不是直接用 `MaterialPageRoute`）
///
/// `MaterialPageRoute` 的转场时长是**写死的**（300ms 左右），
/// 没法跟着用户在设置里调的"动效节奏"变。
/// 而"丝滑补帧"的关键之一就是时长要够长 —— 所以这里用 `PageRouteBuilder`
/// 显式指定时长，值从 [MotionScope] 取。
///
/// 转场效果本身与主题里注册的 [AppPageTransitionsBuilder] **共用同一段代码**
/// （[buildAppPageTransition]），所以走这条路的页面和走主题默认转场的页面
/// 观感完全一致，不会出现"有的页面滑得好看、有的很生硬"。
///
/// 用 `MotionScope.resolve`（不注册依赖）而不是 `of`：
/// 这是在点击回调里调用的，往当前 element 上挂依赖没有意义。
Future<T?> pushAppPage<T>(BuildContext context, Widget page) {
  final Motion motion = MotionScope.resolve(context);

  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      transitionDuration: motion.pageEnter,
      reverseTransitionDuration: motion.pageExit,
      pageBuilder: (
        BuildContext _,
        Animation<double> _,
        Animation<double> _,
      ) =>
          page,
      transitionsBuilder: (
        BuildContext ctx,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget child,
      ) =>
          buildAppPageTransition(ctx, animation, secondaryAnimation, child),
    ),
  );
}
