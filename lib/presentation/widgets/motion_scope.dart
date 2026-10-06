import 'package:flutter/widgets.dart';

import '../../core/theme/motion_tokens.dart';
import '../../domain/settings/motion_settings.dart';

/// 已经把倍率算进去的**最终动效参数** —— 供组件直接取用。
///
/// `MotionTokens` 里是基准值，这里是"用户当前设置下真正该用的值"。
/// 组件拿到 [Motion] 后直接 `duration: motion.pageEnter` 即可，
/// 不需要自己乘倍率（乘的地方只有一处，不会算错也不会漏算）。
@immutable
class Motion {
  const Motion({
    required this.settings,
    required this.pageEnter,
    required this.pageExit,
    required this.navSwitch,
    required this.sheetEnter,
    required this.sheetExit,
    required this.dialog,
    required this.press,
    required this.standard,
  });

  /// 按用户设置换算出一整套时长
  factory Motion.from(MotionSettings settings) => Motion(
        settings: settings,
        pageEnter: settings.of(MotionTokens.pageEnter),
        pageExit: settings.of(MotionTokens.pageExit),
        navSwitch: settings.of(MotionTokens.navSwitch),
        sheetEnter: settings.of(MotionTokens.sheetEnter),
        sheetExit: settings.of(MotionTokens.sheetExit),
        dialog: settings.of(MotionTokens.dialog),
        press: settings.of(MotionTokens.press),
        standard: settings.of(MotionTokens.standard),
      );

  /// 默认档（从容）。测试环境 / 没有 MotionScope 时用它兜底，
  /// 保证任何组件单独拿出来都能正常渲染，不会因为缺 scope 崩掉。
  static final Motion fallback = Motion.from(MotionSettings.defaults);

  final MotionSettings settings;

  final Duration pageEnter;
  final Duration pageExit;

  /// 底部导航切页
  final Duration navSwitch;

  final Duration sheetEnter;
  final Duration sheetExit;
  final Duration dialog;

  /// 按压反馈时长。**它不跟着倍率放大太多** ——
  /// 手指按下去要立刻有反应，等 200ms 才缩放会显得"点不动"。
  final Duration press;

  final Duration standard;

  /// 列表第 [index] 项的入场延迟（逐项错开）。
  /// 上限由 [MotionTokens.maxStaggerSteps] 兜住，长列表不会等到天荒地老。
  Duration staggerDelay(int index) {
    final int step =
        index.clamp(0, MotionTokens.maxStaggerSteps).toInt();
    return settings.of(MotionTokens.stagger * step);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Motion &&
          other.pageEnter == pageEnter &&
          other.pageExit == pageExit &&
          other.navSwitch == navSwitch &&
          other.sheetEnter == sheetEnter &&
          other.sheetExit == sheetExit &&
          other.dialog == dialog &&
          other.press == press &&
          other.standard == standard;

  @override
  int get hashCode => Object.hash(
        pageEnter,
        pageExit,
        navSwitch,
        sheetEnter,
        sheetExit,
        dialog,
        press,
        standard,
      );
}

/// 把当前动效参数注入整棵树。
///
/// 为什么用 InheritedWidget 而不是让每个组件都 `ref.watch`：
/// 动效参数要被**几十个纯展示组件**（按钮、卡片、弹层）读取，
/// 全都改成 ConsumerWidget 会把 Riverpod 的依赖关系铺得到处都是。
/// 用 InheritedWidget 让组件只管"从最近的 scope 拿参数"，干净得多。
class MotionScope extends InheritedWidget {
  const MotionScope({
    super.key,
    required this.motion,
    required super.child,
  });

  final Motion motion;

  /// 取当前动效参数（**会注册依赖**，用于 `build` 里）。
  ///
  /// 拿不到 scope 时回退到默认档，而不是抛错 ——
  /// 组件单测里往往只 pump 一个孤立的 widget，不该因此失败。
  static Motion of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MotionScope>()?.motion ??
      Motion.fallback;

  /// 取当前动效参数（**不注册依赖**，用于点击回调 / 路由 push 这类非 build 时机）。
  ///
  /// 在事件回调里用 [of] 也能跑，但会往当前 element 上挂一个无意义的依赖，
  /// 那个 element 之后会因为动效设置变化而重建 —— 纯属浪费。所以分开。
  static Motion resolve(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MotionScope>()?.motion ??
      Motion.fallback;

  @override
  bool updateShouldNotify(MotionScope oldWidget) => oldWidget.motion != motion;
}
