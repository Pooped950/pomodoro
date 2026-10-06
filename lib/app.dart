import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'data/services/keepalive_service.dart';
import 'presentation/pages/shell/app_shell.dart';
import 'presentation/providers/app_settings_provider.dart';
import 'presentation/providers/timer_provider.dart';
import 'presentation/widgets/motion_scope.dart';

/// 应用根组件
///
/// 动态取色（方案 6.5④）：优先使用系统壁纸提取的主题色（HyperOS 支持
/// Material You），拿不到时回退到内置番茄红。
class PomodoroApp extends ConsumerWidget {
  const PomodoroApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 主题模式来自设置（M4 外观），改了立即生效并落库
    final ThemeMode themeMode = ref.watch(appThemeModeProvider).themeMode;

    // 动效节奏（设置里的滑动条）。在这里换算成最终时长并注入整棵树，
    // 之后任何组件都用 `MotionScope.of(context)` 取，不再各算各的。
    // MotionScope 包在 MaterialApp **外面** —— 这样 Navigator push 出来的
    // 二级页面也是它的后代，同样能取到参数。
    final Motion motion =
        Motion.from(ref.watch(motionSettingsProvider));

    return MotionScope(
      motion: motion,
      child: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          // dynamic_color 2.x 给出的 ColorScheme 来自 material_ui 包，
          // 与 Flutter 自家的 ColorScheme 不是同一个类，无法直接传入主题。
          // 因此只取壁纸提取出的主色作为种子，用 Flutter 自己的
          // ColorScheme.fromSeed 重新生成完整方案 —— 视觉上依然"跟随壁纸"。
          final Color lightSeed = lightDynamic?.primary ?? AppTheme.seed;
          final Color darkSeed = darkDynamic?.primary ?? AppTheme.seed;
          return MaterialApp(
            title: '一颗番茄',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.from(ColorScheme.fromSeed(seedColor: lightSeed)),
            darkTheme: AppTheme.from(
              ColorScheme.fromSeed(
                seedColor: darkSeed,
                brightness: Brightness.dark,
              ),
            ),
            themeMode: themeMode,
            home: const _LayoutProbe(child: _LifecycleScope(child: AppShell())),
          );
        },
      ),
    );
  }
}

/// 启动时把 Flutter 实际看到的窗口尺寸打一条日志。
///
/// ## 为什么需要这个
///
/// 2026-10-06 真机实测：**每一页的内容都整体左偏了 20dp，屏幕右边 20dp 是黑的**。
/// 从截图量出来的证据是明确的（圆环中心在 x=539.5 而屏幕中心是 600、
/// 主按钮跨 x=0..1079），但"为什么"没法靠推断 ——
/// 可能是 `MediaQuery` 报的宽度和实际渲染面不一致，也可能是窗口本身被缩了。
///
/// 所以直接让 App 自己把数字报出来：`View.physicalSize`（引擎拿到的物理尺寸）、
/// `MediaQuery.size`（布局用的逻辑尺寸）、以及各种 padding。
/// 三者对不上，问题在哪就一目了然了。
///
/// 只在 debug 构建里打印（`debugPrint` 在 release 下不输出），
/// 定位完就可以留着 —— 以后再遇到"某个机型上偏了"能直接查。
class _LayoutProbe extends StatefulWidget {
  const _LayoutProbe({required this.child});

  final Widget child;

  @override
  State<_LayoutProbe> createState() => _LayoutProbeState();
}

class _LayoutProbeState extends State<_LayoutProbe> {
  bool _logged = false;
  bool _constraintsLogged = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logged) return;
    _logged = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // 用 var 而不是写死 FlutterView 类型：FlutterView 在 dart:ui 里，
      // 这里只想要它的数字，不需要为它多引一个库
      final view = View.of(context);
      final MediaQueryData mq = MediaQuery.of(context);

      // ⚠️ 全部打印**数字**，不要打印 Size / EdgeInsets 对象本身 ——
      // release(AOT) 下这些类的 toString 会被裁掉，日志会变成
      // "Instance of 'Size'"，等于没打（2026-10-06 踩到）
      debugPrint('[LAYOUT] viewId=${view.viewId} '
          'physical=${view.physicalSize.width}x${view.physicalSize.height} '
          'viewDpr=${view.devicePixelRatio}');
      debugPrint('[LAYOUT] mqSize=${mq.size.width}x${mq.size.height} '
          'mqDpr=${mq.devicePixelRatio} '
          'mqSizePx=${mq.size.width * mq.devicePixelRatio}'
          'x${mq.size.height * mq.devicePixelRatio}');
      debugPrint('[LAYOUT] padding L=${mq.padding.left} T=${mq.padding.top} '
          'R=${mq.padding.right} B=${mq.padding.bottom}');
      debugPrint('[LAYOUT] viewPadding L=${mq.viewPadding.left} '
          'T=${mq.viewPadding.top} R=${mq.viewPadding.right} '
          'B=${mq.viewPadding.bottom}');
      debugPrint('[LAYOUT] viewInsets L=${mq.viewInsets.left} '
          'T=${mq.viewInsets.top} R=${mq.viewInsets.right} '
          'B=${mq.viewInsets.bottom}');
      debugPrint('[LAYOUT] views='
          '${WidgetsBinding.instance.platformDispatcher.views.length} '
          'brightness=${mq.platformBrightness}');
    });
  }

  @override
  Widget build(BuildContext context) {
    // 把布局真正拿到的约束也报出来。MediaQuery 说多少是一回事、
    // 约束给多少是另一回事 —— 两者对不上就说明中间有东西改了约束。
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        if (!_constraintsLogged) {
          _constraintsLogged = true;
          debugPrint('[LAYOUT] rootConstraints '
              'max=${c.maxWidth}x${c.maxHeight} '
              'min=${c.minWidth}x${c.minHeight}');
        }

        // 2026-10-06 的"全 App 左偏 20dp"排查曾在这里画左右边缘 + 中线彩条
        // 辅助定位（真凶是页面转场"让位"Tween 写反，已修复并加回归测试
        // test/app_page_transitions_test.dart）。诊断彩条已完成使命，移除。
        return widget.child;
      },
    );
  }
}

/// 监听 App 生命周期：每次回到前台，从原生前台服务拉一次最新计时状态——
/// 用户可能在通知栏按了暂停/继续/跳过（方案 6.5⑥），以服务为准对齐。
class _LifecycleScope extends ConsumerStatefulWidget {
  const _LifecycleScope({required this.child});

  final Widget child;

  @override
  ConsumerState<_LifecycleScope> createState() => _LifecycleScopeState();
}

class _LifecycleScopeState extends ConsumerState<_LifecycleScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 首帧后自动申请一次通知权限。
    //
    // 不申请的话，新装用户如果不主动进「后台保活设置」页，通知权限会一直是关的，
    // 到点提醒会被系统**直接丢弃**（不是静默，是根本不出现）—— 用户只会觉得"这 App 不准"。
    // 原生侧已判断"已授予就直接返回"，所以每次启动调用都是无害的。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(keepAliveServiceProvider).requestNotificationPermission(),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(timerProvider.notifier).syncFromNative();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
