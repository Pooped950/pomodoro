import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/remote/remote_config.dart';
import '../../../domain/stats/stats_summary.dart';
import '../../providers/stats_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/pressable.dart';
import '../manual/about_page.dart';
import '../manual/manual_dialog.dart';
import '../settings/keepalive_page.dart';
import '../settings/settings_detail_page.dart';

/// 「我的」（一级页）
///
/// ## 为什么改成一堆入口而不是直接把设置堆在这里
///
/// 产品要求：设置收纳进「我的 → 设置」的二级目录，而不是把 6 组控件
/// （计时 5 项、提醒 2 项、主题、背景 9 个色卡、动效滑动条、保活、课表、关于）
/// 直接堆在一页里滚很久。
///
/// 现在这页只回答一个问题：**"我想干什么"** ——
/// 调参数去「设置」，修保活去「后台保活」，导课表去「导入课表」。
/// 具体每一项数值长什么样，进去再说。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<StatsData> async = ref.watch(statsProvider);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
          child: ListView(
            // 底部给悬浮导航条留空间（Scaffold 开了 extendBody）
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.tight,
              AppSpacing.page,
              kBottomNavSpace,
            ),
            children: <Widget>[
              // ⚠️ 文案统一走 t()：远程配置里给同名 key 就能改，不用发版
              Text(t('我的'), style: text.titleLarge),
              const SizedBox(height: AppSpacing.section),

              _SummaryCard(data: async.value),

              const SizedBox(height: AppSpacing.section),
              AppCard(
                padding: EdgeInsets.zero,
                child: _NavRow(
                  icon: Icons.tune_rounded,
                  title: t('设置'),
                  subtitle: t('计时 · 提醒 · 外观 · 背景 · 动效'),
                  onTap: () => pushAppPage(context, const SettingsDetailPage()),
                ),
              ),

              const SizedBox(height: AppSpacing.section),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    _NavRow(
                      icon: Icons.shield_moon_outlined,
                      title: t('后台保活设置'),
                      subtitle: t('息屏后到点提醒能否可靠工作，取决于这几项'),
                      onTap: () =>
                          pushAppPage(context, const KeepAlivePage()),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.section),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    _NavRow(
                      icon: Icons.menu_book_outlined,
                      title: t('使用手册'),
                      subtitle: t('计时 · 任务 · 统计 · 课表 · 保活设置'),
                      onTap: () => showManualDialog(context),
                    ),
                    const _RowDivider(),
                    _NavRow(
                      icon: Icons.info_outline_rounded,
                      title: t('关于'),
                      subtitle: '版本 $kAppVersion',
                      onTap: () => pushAppPage(context, const AboutPage()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部摘要：让「我的」不至于只有几个入口、空荡荡的。
///
/// 数据直接复用统计页的 `statsProvider`（近 7 天窗口），不额外查库 ——
/// 这一页打开时统计页大概率已经在后台算过了。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});

  /// null = 还在加载 / 读失败
  final StatsData? data;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    final StatsData d = data ?? StatsData.empty;
    final bool ready = data != null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            ready ? '你的专注' : '正在读取…',
            style: text.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _SummaryItem(
                  label: '今天',
                  pomodoros: d.today.completedPomodoros,
                  seconds: d.today.focusSeconds,
                ),
              ),
              Container(
                width: 1,
                height: 34,
                color: scheme.onSurface.withValues(alpha: 0.08),
              ),
              Expanded(
                child: _SummaryItem(
                  label: '近 $kStatsWindowDays 天',
                  pomodoros: _weekPomodoros(d),
                  seconds: d.weekTotalSeconds,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static int _weekPomodoros(StatsData d) {
    int n = 0;
    for (final DailyFocus day in d.week) {
      n += day.completedPomodoros;
    }
    return n;
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.pomodoros,
    required this.seconds,
  });

  final String label;
  final int pomodoros;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: text.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                '$pomodoros',
                style: text.titleLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const <FontFeature>[FontFeature('tnum')],
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '个',
                style: text.bodySmall?.copyWith(
                  color: scheme.primary.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  formatDurationHuman(seconds),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.55),
                    fontFeatures: const <FontFeature>[FontFeature('tnum')],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 「图标 + 标题/说明 + 箭头」的导航行
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    // 用 Pressable 而不是 InkWell：水波纹是 Android 语言，
    // 和这个 App 的玻璃材质放在一起很出戏（详见 Pressable 的注释）。
    // 这里用"整块底色渐显"——按下去这一行整体亮一下，像材料受压。
    return Pressable(
      onTap: onTap,
      highlightColor: scheme.primary.withValues(alpha: 0.07),
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
