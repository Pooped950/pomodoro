import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/motion_tokens.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../providers/stats_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/ambient_background.dart';
import '../../widgets/floating_nav_bar.dart';
import '../../widgets/motion_scope.dart';
import '../home/home_page.dart';
import '../manual/manual_content.dart';
import '../manual/update_dialog.dart';
import '../manual/manual_dialog.dart';
import '../profile/profile_page.dart';
import '../taskstats/task_stats_page.dart';
import '../timetable/timetable_page.dart';

/// 应用外壳：环境色背景 + 可滑动页面 + 悬浮导航条。
///
/// ## 为什么用 Stack 而不是 Scaffold 的 bottomNavigationBar
///
/// 玻璃靠 `BackdropFilter` 模糊**背后**的内容，所以导航条必须和
/// 环境色背景、页面内容处在同一棵绘制树里，且排在它们之后绘制。
/// 把导航条放进 Scaffold 的 `bottomNavigationBar` 槽位会把它从 body
/// 的绘制树里拆出去，模糊就取不到环境色了。
///
/// 所以这里统一用 Stack：环境色 → 页面 → 导航条，绘制顺序一目了然。
///
/// 副作用：各页面底部要自己预留 [kBottomNavSpace] 的空间，
/// 否则最后一项内容会被导航条盖住。**新增页面时不要忘记。**
///
/// ## 为什么用 PageView 而不是 IndexedStack（2026-10-05 改）
///
/// 原来用 `IndexedStack` + `setState` 切换，效果是**瞬切**，很生硬。
/// 现在换成 `PageView`：
///   - 可以左右滑动切页，页面**跟着手指走**
///   - 点导航条时用 `animateToPage` 平滑滑过去，不是跳过去
///   - 滑动过程中把连续的页偏移量传给导航条，指示器实时跟随
///
/// 副作用：`PageView` 会回收不可见的页面。这里用 [_KeepAlivePage] 包一层
/// 保持各页存活 —— 不这么做的话，从计时页滑走再滑回来，滚动位置之类会丢。
///
/// ## 保活的代价：数据不会自己刷新（2026-10-05 补）
///
/// 页面被保活之后，切回来时**不会重建**，也就不会重新取数。
/// 表现是"刚跑完一个番茄，切到统计页还是旧数字"。所以在切页时主动
/// 让对应数据源失效（见 [_refreshFor]）。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// 第二格：「任务 + 统计」合并成一页，页内两个小标签切换。
  ///
  /// 2026-10-06 由用户提出 —— 原来「任务」「统计」各占一格，
  /// 现在合并，腾出的第三格给课表。
  static const int _combinedIndex = 1;

  static const int _settingsIndex = 3;

  final PageController _controller = PageController();

  /// 连续页偏移量（0.0 = 第一页，0.5 = 滑到一半）。
  ///
  /// ⚠️ 用 `ValueNotifier` 而不是 `setState`：拖动时它**每帧都在变**，
  /// 用 setState 会把整个外壳（含 PageView）每帧重建一遍 ——
  /// 120Hz 下每帧只有 8.3ms 预算，很容易爆掉，滑动就掉帧
  /// （2026-10-05 用户真机反馈"帧率低、和系统原生不符合"）。
  /// 改成只让导航条订阅它，重建范围缩到最小。
  final ValueNotifier<double> _pageOffset = ValueNotifier<double>(0);

  int _index = 0;

  /// 页面只构建一次：避免任何重建路径造成不必要的 widget 替换。
  late final List<Widget> _pages = <Widget>[
    _KeepAlivePage(child: HomePage(onOpenSettings: () => _goTo(_settingsIndex))),
    // 第二格：任务 + 统计合并（2026-10-06）
    const _KeepAlivePage(child: TaskStatsPage()),
    // 第三格：课表（顶掉原来的「统计」）
    const _KeepAlivePage(child: TimetablePage()),
    const _KeepAlivePage(child: ProfilePage()),
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    // 首帧之后再弹手册 —— 让页面先画出来，弹层是"盖在界面上"出现的，
    // 不是跟着第一帧一起挤进来
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeShowStartupDialogs());
  }

  /// 首次打开（或者手册版本升了）时弹一次使用手册。
  ///
  /// 为什么放在外壳而不是 `HomePage` 里：手册讲的是**整个 App**，
  /// 不是计时页一个页面；而且外壳能保证不管用户从哪一格进来都只弹一次。
  ///
  /// 弹过就立刻记下版本 —— 用户是滑完还是点「跳过」都算"看过了"，
  /// 不该下次启动再弹一次烦他。
  /// 启动时的两类弹窗，**更新说明在手册之前判**：
  /// 全新安装（没看过手册）只弹手册不弹更新，判定要用"看没看过手册"，
  /// 所以必须抢在手册把"看过"写进设置之前。
  Future<void> _maybeShowStartupDialogs() async {
    await _maybeShowUpdateDialog();
    await _maybeShowManual();
  }

  /// 大版本升级后的老用户：弹一次「vX 更新了什么」。
  /// 全新安装不弹（手册已经把一切讲了一遍），看过这个大版本就不再弹。
  Future<void> _maybeShowUpdateDialog() async {
    final SettingsRepository settings =
        ref.read(settingsRepositoryProvider);
    final String? seen =
        await settings.readString(SettingsRepository.keyUpdateSeenVersion);
    if (!shouldShowMajorUpdateDialog(seen, kAppVersion)) return;
    // 手册从没弹过 = 全新安装：更新说明对他是噪音，直接记版本
    final String? manualSeen =
        await settings.readString(SettingsRepository.keyManualSeenVersion);
    if (manualSeen == null) {
      await settings.writeString(
          SettingsRepository.keyUpdateSeenVersion, kAppVersion);
      return;
    }
    if (kDebugMode) {
      debugPrint('[UPDATE] 大版本升级（见过 ${seen ?? '无'} → $kAppVersion）弹更新说明');
    }
    if (!mounted) return;
    await showUpdateDialog(context);
    await settings.writeString(
      SettingsRepository.keyUpdateSeenVersion,
      kAppVersion,
    );
  }

  Future<void> _maybeShowManual() async {
    final SettingsRepository settings =
        ref.read(settingsRepositoryProvider);
    final String? seen =
        await settings.readString(SettingsRepository.keyManualSeenVersion);

    // debug 构建下打一行：排查"手册该弹却没弹"时，一眼看出是版本对上了
    // 还是别的原因（release 不输出）
    if (kDebugMode) {
      debugPrint('[MANUAL] 已看过=${seen ?? '(没看过)'} '
          '当前=$kManualVersion → '
          '${seen == kManualVersion ? '不弹' : '弹'}');
    }

    if (seen == kManualVersion) return;
    if (!mounted) return;

    await showManualDialog(context, isFirstLaunch: true);
    await settings.writeString(
      SettingsRepository.keyManualSeenVersion,
      kManualVersion,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    _pageOffset.dispose();
    super.dispose();
  }

  /// PageController 每帧回调：把连续偏移量喂给导航条。
  /// 只写 ValueNotifier，不 setState —— 见 [_pageOffset] 的说明。
  void _onScroll() {
    if (!_controller.hasClients) return;
    final double? page = _controller.page;
    if (page != null) _pageOffset.value = page;
  }

  /// 点导航条：平滑滑过去，不瞬切。
  /// 时长走动效规范（用户在设置里调"动效节奏"，这里跟着变）。
  void _goTo(int index) {
    if (index == _index) return;
    _controller.animateToPage(
      index,
      duration: MotionScope.resolve(context).navSwitch,
      curve: MotionTokens.emphasized,
    );
  }

  /// 切到某一页时，让该页的数据源失效/刷新。
  ///
  /// 因为页面被 [_KeepAlivePage] 保活，切回来不会重建、也就不会重新取数。
  /// 不主动刷的话，"刚跑完一个番茄 → 切到统计页"看到的还是旧数字。
  void _refreshFor(int index) {
    if (index == _combinedIndex) {
      // 统计是 FutureProvider：invalidate 会保留上一次的值（不会闪骨架），
      // 新数据回来后如果和旧的一样，柱状图也不会重播动画（见 _sameSeries）
      ref.invalidate(statsProvider);
      // 任务可能被后台的番茄计数改动过（原生服务在后台推进了阶段）
      unawaited(ref.read(taskListProvider.notifier).refresh());
    }
    // 课表页（第三格）不依赖任何会自己变的数据，不用刷
  }

  @override
  Widget build(BuildContext context) {
    // 手势条 / 三键导航的安全距离
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    final double navBottom =
        bottomInset > AppSpacing.tight ? bottomInset : AppSpacing.tight;

    return Scaffold(
      // 背景交给 AmbientBackground 画，Scaffold 自己不铺色
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              // RepaintBoundary：把「页面内容」和「导航条 / 背景」分成两个独立图层。
              // 不加的话，页面里任何滚动/动画的重绘都会连带把导航条的
              // BackdropFilter 和整块环境色背景重新光栅化一遍 ——
              // 120Hz 下 8.3ms 的预算经不起这么花（2026-10-06 真机实测反馈帧率不足）
              child: RepaintBoundary(
                child: PageView(
                  controller: _controller,
                  // 一次滑一页，不连跳；惯性由 Flutter 默认物理曲线处理
                  physics: const PageScrollPhysics(),
                  onPageChanged: (int i) {
                    setState(() => _index = i);
                    _refreshFor(i);
                  },
                  children: _pages,
                ),
              ),
            ),
            Positioned(
              left: AppSpacing.page,
              right: AppSpacing.page,
              bottom: navBottom,
              // 只有导航条订阅页偏移量 —— 拖动时重建范围就限制在这一块，
              // 不牵动上面的 PageView（这是滑动掉帧的根因）
              child: RepaintBoundary(
                child: ValueListenableBuilder<double>(
                  valueListenable: _pageOffset,
                  builder: (BuildContext context, double offset, Widget? _) {
                    return FloatingNavBar(
                      currentIndex: _index,
                      pageOffset: offset,
                      onChanged: _goTo,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 让 `PageView` 里的页面保持存活。
///
/// `PageView` 默认回收不可见页面。计时页虽然状态都在 Riverpod 里不会丢，
/// 但滚动位置、局部 UI 状态会丢 —— 从计时页滑走再滑回来会"跳回顶部"。
/// 这里用一个统一的包装类实现 `AutomaticKeepAliveClientMixin`，
/// 避免去改每一个页面。
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    // AutomaticKeepAliveClientMixin 要求调用 super.build
    super.build(context);
    return widget.child;
  }
}
