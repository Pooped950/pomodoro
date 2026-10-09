import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/motion_tokens.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/update/startup_dialogs.dart';
import '../../../domain/update/update_decision.dart';
import '../../../domain/update/update_info.dart';
import '../../providers/stats_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/update_provider.dart';
import '../../widgets/ambient_background.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/floating_nav_bar.dart';
import '../../widgets/motion_scope.dart';
import '../home/home_page.dart';
import '../manual/manual_content.dart';
import '../manual/update_dialog.dart';
import '../manual/manual_dialog.dart';
import '../profile/profile_page.dart';
import '../taskstats/task_stats_page.dart';
import '../timetable/timetable_page.dart';
import '../update/update_page.dart';

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

    // ⚠️ 强制更新的**补弹**通道（2026-10-09）。
    //
    // 启动检查为了不阻塞首帧只等 1.2 秒（见 `_maybeShowStartupDialogs`），
    // 学校 WiFi 慢的时候 1.2 秒根本拉不到 `version.json` ——
    // 那时 `state.action` 还是默认值，**强制更新弹窗就漏掉了**。
    // 所以这里挂个监听：后台那次检查跑完、action 变成 forceUpdate 时补弹。
    _updateSub = ref.listenManual<UpdateState>(
      updateStateProvider,
      (UpdateState? _, UpdateState next) {
        if (!mounted) return;
        if (next.action == UpdateAction.forceUpdate &&
            !_forceDialogShown &&
            next.remote != null) {
          _forceDialogShown = true;
          unawaited(_showRemoteUpdateDialog(next));
        }
      },
    );
  }

  /// 强制更新弹窗只弹一次（用户点「立即更新」进更新页后不该再被盖一层）
  bool _forceDialogShown = false;

  /// 启动检查的订阅（dispose 时要退掉）
  ProviderSubscription<UpdateState>? _updateSub;

  /// 启动时要弹的窗：**远端更新说明 → 本地大版本兜底 → 首次手册**。
  ///
  /// 取舍与顺序交给纯函数 [planStartupDialogs]（可单测），这里只负责执行：
  ///   - 先**静默**检查一次远端版本（有 10 分钟节流；失败静默，绝不打扰）
  ///   - 远端要求提示就弹远端那份，本地兜底让位（否则用户连看两个几乎一样的窗）
  ///   - 手册永远最后弹：先讲"变了什么"，再教"怎么用"
  ///
  /// ⚠️ 「全新安装」的判据是"手册还没弹过"，所以两个键都要在动手之前读完。
  Future<void> _maybeShowStartupDialogs() async {
    // ⚠️ 不阻塞启动（评审 I1）：这一步要读网络，网络"挂着不响应"时（学校 WiFi
    // 的常态）会拖满 5 秒超时，首启手册也跟着迟到。所以只等 1.2 秒：
    // 等不到就按"这次没有远端信息"继续，检查在后台跑完照样更新小红点和页面。
    await ref
        .read(updateStateProvider.notifier)
        .checkIfStale()
        .timeout(const Duration(milliseconds: 1200), onTimeout: () {});
    if (!mounted) return;

    final SettingsRepository settings = ref.read(settingsRepositoryProvider);
    final String? manualSeen =
        await settings.readString(SettingsRepository.keyManualSeenVersion);
    final String? seen =
        await settings.readString(SettingsRepository.keyUpdateSeenVersion);

    final bool localMajorDue = shouldShowMajorUpdateDialog(
      isFreshInstall: manualSeen == null,
      seenVersion: seen,
      currentVersion: kAppVersion,
    );

    final UpdateState state = ref.read(updateStateProvider);
    final List<StartupDialog> plan = planStartupDialogs(
      remoteAction: state.action,
      localMajorDue: localMajorDue,
      manualDue: manualSeen != kManualVersion,
    );
    if (kDebugMode) {
      debugPrint('[STARTUP] 计划=$plan（远端=${state.action} '
          '本地major=$localMajorDue 手册=${manualSeen ?? '(没看过)'}）');
    }

    for (final StartupDialog dialog in plan) {
      if (!mounted) return;
      switch (dialog) {
        case StartupDialog.remoteUpdate:
          await _showRemoteUpdateDialog(state);
        case StartupDialog.localMajorUpdate:
          await showUpdateDialog(context);
          await settings.writeString(
              SettingsRepository.keyUpdateSeenVersion, kAppVersion);
        case StartupDialog.manual:
          await showManualDialog(context, isFirstLaunch: true);
          await settings.writeString(
              SettingsRepository.keyManualSeenVersion, kManualVersion);
      }
    }

    // 全新安装 / 本地是脏数据：把当前版本记一笔，免得下次被当成
    // "这个键不存在"而误弹（远端那份弹过也会自己记）
    if (seen != kAppVersion && (seen == null || majorVersionOf(seen) == null)) {
      await settings.writeString(
          SettingsRepository.keyUpdateSeenVersion, kAppVersion);
    }
  }

  /// 远端驱动的那份更新说明：`prompt` 可关、`force` 关不掉
  Future<void> _showRemoteUpdateDialog(UpdateState state) async {
    final UpdateInfo? remote = state.remote;
    if (remote == null) return;
    final bool force = state.action == UpdateAction.forceUpdate;
    // 记一笔：force 档从 initState 的监听里补弹时不要重复
    if (force) _forceDialogShown = true;

    await showUpdateDialog(
      context,
      version: remote.versionName,
      notes: remote.notes.isEmpty ? null : remote.notes,
      force: force,
      // 两档都给"去更新"的入口：prompt 档原来只传了文案、没有动作（评审 I5）
      onUpdate: () => pushAppPage(context, const UpdatePage()),
    );

    // prompt 档：记下"这个版本弹过了"，同一个版本不再弹
    if (!force) {
      await ref.read(updateStateProvider.notifier).markPrompted();
    }
  }

  @override
  void dispose() {
    _updateSub?.close();
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
