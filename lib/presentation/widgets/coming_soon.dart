import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import 'app_card.dart';

/// 占位页。
///
/// P0 阶段任务 / 统计 / 我的三个页面还没实现，
/// 用一个统一的占位页保证导航结构完整、观感不塌。
/// 每个占位页明确写出"这个页面将来长什么样"，方便后续按图施工。
class ComingSoon extends StatelessWidget {
  const ComingSoon({
    super.key,
    required this.title,
    required this.icon,
    required this.description,
    required this.bullets,
  });

  final String title;
  final IconData icon;
  final String description;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
          child: SingleChildScrollView(
            // 底部给悬浮导航条留空间（Scaffold 开了 extendBody）
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.page,
              AppSpacing.page,
              kBottomNavSpace,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: text.titleLarge),
                const SizedBox(height: AppSpacing.section),
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.section),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppRadius.chip),
                        ),
                        child: Icon(icon, color: scheme.primary, size: 24),
                      ),
                      const SizedBox(height: AppSpacing.item),
                      Text('此页面尚未实现', style: text.titleMedium),
                      const SizedBox(height: AppSpacing.tight),
                      Text(
                        description,
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.item),
                      for (final String b in bullets)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Padding(
                                padding: const EdgeInsets.only(top: 7),
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: scheme.onSurface.withValues(alpha: 0.3),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  b,
                                  style: text.bodySmall?.copyWith(
                                    color: scheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            ],
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
    );
  }
}
