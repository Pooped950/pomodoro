import 'package:flutter/material.dart';

import '../../../core/app_info.dart';
import '../../../core/theme/design_tokens.dart';
import '../../widgets/ambient_background.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/glass_primary_button.dart';
import '../../widgets/pressable.dart';
import '../../widgets/update_row.dart';
import '../update/update_page.dart';
import 'manual_dialog.dart';

/// 「关于」页 —— 从「我的 → 关于」进来。
///
/// ## 为什么单独开一页，而不是塞在「我的」里
///
/// 「我的」是"我想干什么"的入口页（见 `ProfilePage` 的注释），
/// 而"这个 App 是什么、怎么看说明书"是**看**的东西，
/// 堆在入口页里会把那一页越撑越长。
///
/// 这一页干三件事：
///   1. 说清楚它是什么（名称 / 版本 / 一句话）
///   2. 给一个**随时翻手册**的入口（首启那个弹窗之后还能找回来）
///   3. **检查更新**（2026-10-07 从「我的」挪进来的，见下面的注释）
///
/// ⚠️ 2026-10-07 用户要求：这一页**不再出现**开源协议、数据存储相关的
/// 字样 —— 以后产品形态可能变（闭源收费 / 数据上传），页面文案只写
/// 当下不会变的事实（名称 / 版本 / 手册入口）。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

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
                  Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: '返回',
                      ),
                      Expanded(
                        child: Text('关于', style: text.titleMedium),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.tight),

                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.section),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(AppRadius.cardMedium),
                          ),
                          child: Icon(
                            Icons.spa_outlined,
                            color: scheme.primary,
                            size: 26,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.item),
                        Text(kAppName, style: text.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          '版本 $kAppVersion',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.item),
                        Text(
                          '一个用「专注 / 休息」节奏工作的番茄钟。',
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.item),

                  // 手册入口：首启弹过之后，从这里还能翻到
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: _AboutRow(
                      icon: Icons.menu_book_outlined,
                      title: '使用手册',
                      subtitle: '计时 · 任务 · 统计 · 课表 · 保活设置',
                      onTap: () => showManualDialog(context),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.item),

                  // 检查更新：2026-10-07 用户要求从「我的」一级页挪到这里 ——
                  // 「我的」是"我想干什么"的入口页，而"这个 App 本身有没有新版"
                  // 属于「关于」的范畴（和版本号挨着才讲得通）
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: UpdateRow(
                      onTap: () => pushAppPage(context, const UpdatePage()),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.section),
                  GlassPrimaryButton(
                    label: '看一遍使用手册',
                    icon: Icons.menu_book_outlined,
                    accent: scheme.primary,
                    onPressed: () => showManualDialog(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 「图标 + 标题/说明 + 箭头」的导航行（和「我的」页同一套）
class _AboutRow extends StatelessWidget {
  const _AboutRow({
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
