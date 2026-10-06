import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../data/services/keepalive_service.dart';
import '../../widgets/ambient_background.dart';
import '../../widgets/app_card.dart';
import '../../widgets/fade_slide_in.dart';

/// 「后台保活设置」页（M3 阶段四）。
///
/// ## 这页存在的理由
///
/// 澎湃OS / MIUI 的后台管理比原生激进：**光有前台服务和精确闹钟不够**。
/// 用户不手动开「自启动」、不把「省电策略」设为无限制，息屏后进程会被系统杀掉，
/// 到点提醒自然不响 —— 而且失败得很安静，用户只会觉得"这 App 不准"。
///
/// 这些开关**没有公开 API 可改**（自启动甚至是 MIUI 的私有 AppOps），
/// 所以能做的只有两件事：**如实查状态 + 一键跳到对应系统页面**。
class KeepAlivePage extends ConsumerStatefulWidget {
  const KeepAlivePage({super.key});

  @override
  ConsumerState<KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends ConsumerState<KeepAlivePage>
    with WidgetsBindingObserver {
  KeepAliveStatus? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置页回来时自动重新查状态，用户不用手动刷新
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final KeepAliveStatus s = await ref.read(keepAliveServiceProvider).status();
    if (!mounted) return;
    setState(() {
      _status = s;
      _loading = false;
    });
  }

  Future<void> _run(Future<bool> Function() action) async {
    final bool ok = await action();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('没找到对应的系统页面，请到「设置 → 应用设置 → 番茄钟」里手动开启'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final KeepAliveStatus s = _status ?? KeepAliveStatus.unknown();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.tight,
                  AppSpacing.page,
                  AppSpacing.section,
                ),
                children: <Widget>[
                  // 内容逐项入场（淡入 + 从下方轻推上来，依次错开）。
                  //
                  // 用户的原话是「点击后台保活设置以后跳出来的界面太快了，
                  // 我要你做好动画衔接效果补帧」。光把页面转场拉长还不够 ——
                  // 页面滑进来时里面是"已经摆好"的一整块，仍然像贴图。
                  // 让内容在页面落位的过程中依次浮现，才有"这个界面是被
                  // 组装出来的"的连贯感。
                  FadeSlideIn(
                    index: 0,
                    child: _Header(
                      title: '后台保活设置',
                      loading: _loading,
                      onBack: () => Navigator.of(context).maybePop(),
                      onRefresh: _refresh,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),

                  // 全绿 / 待办 的总体提示
                  FadeSlideIn(index: 1, child: _SummaryBanner(status: s)),
                  const SizedBox(height: AppSpacing.section),

                  FadeSlideIn(
                    index: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const _SectionLabel('四项开关'),
                        AppCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: <Widget>[
                              _KeepAliveRow(
                                icon: Icons.notifications_active_outlined,
                                title: '通知权限',
                                subtitle: '关掉后所有提醒都会被系统丢弃，到点响不了',
                                state: s.notificationsEnabled,
                                onTap: () async {
                                  final KeepAliveService svc =
                                      ref.read(keepAliveServiceProvider);
                                  if (!s.notificationsEnabled) {
                                    // 先弹系统对话框；用户拒绝过就不再弹，改跳设置页
                                    await svc.requestNotificationPermission();
                                    await _refresh();
                                    if (!mounted) return;
                                    final KeepAliveStatus now =
                                        await svc.status();
                                    if (!mounted) return;
                                    if (!now.notificationsEnabled) {
                                      await _run(svc.openNotificationSettings);
                                    }
                                  } else {
                                    await _run(svc.openNotificationSettings);
                                  }
                                },
                              ),
                              const _RowDivider(),
                              _KeepAliveRow(
                                icon: Icons.autorenew_rounded,
                                title: '自启动',
                                subtitle: '澎湃OS 必须开，否则后台服务起不来',
                                state: s.autoStartAllowed,
                                onTap: () => _run(ref
                                    .read(keepAliveServiceProvider)
                                    .openAutoStartSettings),
                              ),
                              const _RowDivider(),
                              _KeepAliveRow(
                                icon: Icons.battery_saver_outlined,
                                title: '省电策略 · 无限制',
                                subtitle: '不设无限制的话，息屏后进程会被系统杀掉',
                                state: s.batteryUnrestricted,
                                onTap: () => _run(ref
                                    .read(keepAliveServiceProvider)
                                    .openBatterySettings),
                              ),
                              const _RowDivider(),
                              _KeepAliveRow(
                                icon: Icons.lock_outline_rounded,
                                title: '锁定后台',
                                subtitle: '在最近任务里下拉本应用卡片加锁',
                                // 没有可查询的状态，也没有对应设置页
                                state: null,
                                manual: true,
                                onTap: () => _showLockHint(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.section),
                  FadeSlideIn(
                    index: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const _SectionLabel('说明'),
                        AppCard(
                          child: Text(
                            s.isMiuiLike
                                ? '澎湃OS 会主动清理后台应用。上面四项都开齐后，'
                                    '息屏计时与到点提醒才稳定。'
                                    '这些开关没有公开接口，只能由你手动开启，'
                                    '本应用无法代劳。'
                                : '系统会限制后台应用。上面四项开齐后，'
                                    '息屏计时与到点提醒才稳定。',
                            style: text.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6),
                              height: 1.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showLockHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('打开最近任务（多任务）界面，把番茄钟的卡片向下拉一下，出现小锁图标即锁定成功'),
        duration: Duration(seconds: 6),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.loading,
    required this.onBack,
    required this.onRefresh,
  });

  final String title;
  final bool loading;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '返回',
        ),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        IconButton(
          onPressed: loading ? null : onRefresh,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: '重新检查',
        ),
      ],
    );
  }
}

/// 顶部总体状态：全绿 / 还有几项待办
class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.status});

  final KeepAliveStatus status;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final bool ok = status.allReady;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: ok
            ? scheme.primary.withValues(alpha: 0.10)
            : scheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.cardMedium),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            color: ok ? scheme.primary : scheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ok
                  ? '四项都已就绪，息屏计时与到点提醒应能正常工作'
                  : '还有 ${status.pendingCount} 项没开，息屏后可能收不到到点提醒',
              style: text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: ok ? scheme.primary : scheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: AppSpacing.tight),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: AppSpacing.item,
      endIndent: AppSpacing.item,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
    );
  }
}

/// 一行保活开关。[state] 为 null 表示状态未知或无法查询。
class _KeepAliveRow extends StatelessWidget {
  const _KeepAliveRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.state,
    required this.onTap,
    this.manual = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// true = 已开，false = 未开，null = 未知 / 需手动确认
  final bool? state;

  /// 该项没有可查询的状态（如「锁定后台」）
  final bool manual;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    final (String label, Color color) = switch (state) {
      true => ('已开启', scheme.primary),
      false => ('未开启', scheme.error),
      null => (manual ? '手动' : '未知', scheme.onSurface.withValues(alpha: 0.45)),
    };

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.item,
          14,
          AppSpacing.tight,
          14,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: scheme.onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: text.bodyMedium),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.5),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                label,
                style: text.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: scheme.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
