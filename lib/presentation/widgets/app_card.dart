import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// 通用大圆角卡片（HyperOS 风格的基础容器）。
///
/// 所有需要"一块内容"的地方都用它，保证圆角和间距全局一致。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.item),
    this.onTap,
    this.radius = AppRadius.card,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final Widget content = Padding(padding: padding, child: child);

    return Material(
      color: elevatedSurface(scheme),
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, child: content),
    );
  }
}
