import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import 'glass_surface.dart';

/// 底部导航项
class NavItem {
  const NavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// 悬浮式底部导航条。
///
/// 设计上对齐 HyperOS 4 的两个点：
///   1. 「柔性悬浮框架」—— 导航条不贴边通栏，而是以悬浮的圆角块存在
///   2. 「柔光玻璃」材质 —— 列表内容从它背后滚过时会被模糊，
///      形成真实的玻璃层次
///
/// 位置由 `AppShell` 的 `Positioned` 决定（左边距、右边距、底部安全区），
/// 本组件只负责玻璃块本身。
///
/// 刻意不用 Material 的 NavigationBar —— 系统那套是通栏 + 顶部指示器，
/// 观感偏原生 Android，和澎湃的悬浮语言不一致。
///
/// ## 滑动跟随（2026-10-05 改）
///
/// 原来选中高亮是**每项各自淡入淡出的方块**，切页时很生硬。现在改成
/// **一个整体滑动的药丸指示器**，位置由 [pageOffset] 驱动：
///   - 手指拖动页面时，`pageOffset` 每帧都在变 → 指示器实时跟着手指走
///   - 点导航条时，切页动画本身会让 `pageOffset` 平滑变化 → 指示器平滑滑过去
/// 图标/文字颜色也按"离指示器多远"连续插值，而不是硬切。
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onChanged,
    this.pageOffset,
    this.items = defaultItems,
  });

  final int currentIndex;
  final ValueChanged<int> onChanged;

  /// 连续页偏移量（0.0 = 第一项，1.5 = 停在第一、二项之间）。
  /// 传 null 时退化为"只按 [currentIndex] 显示"。
  final double? pageOffset;

  final List<NavItem> items;

  static const List<NavItem> defaultItems = <NavItem>[
    NavItem(icon: Icons.timer_outlined, label: '计时'),
    NavItem(icon: Icons.check_circle_outline, label: '任务'),
    NavItem(icon: Icons.bar_chart, label: '统计'),
    NavItem(icon: Icons.person_outline, label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double maxIndex = (items.length - 1).toDouble();
    final double offset =
        (pageOffset ?? currentIndex.toDouble()).clamp(0.0, maxIndex);

    // 外边距和底部安全区由 AppShell 的 Positioned 负责，
    // 这里只负责"玻璃块"本身。
    return GlassSurface(
      radius: AppRadius.card,
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double itemWidth = c.maxWidth / items.length;

              return Stack(
                children: <Widget>[
                  // 滑动指示器：整体一块药丸，位置随 pageOffset 连续变化。
                  // 不需要 AnimatedPositioned —— 拖动时 offset 本身就连续，
                  // 点击切页时切页动画又让 offset 平滑变化。
                  Positioned(
                    left: offset * itemWidth + 2,
                    top: 8,
                    bottom: 8,
                    width: itemWidth - 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.14),
                        borderRadius:
                            BorderRadius.circular(AppRadius.cardMedium),
                      ),
                    ),
                  ),

                  Row(
                    children: <Widget>[
                      for (int i = 0; i < items.length; i++)
                        Expanded(
                          child: _NavBarButton(
                            item: items[i],
                            // 离指示器越近越"选中"：滑动过程中颜色连续过渡，
                            // 而不是等落页了才硬切
                            emphasis:
                                (1 - (offset - i).abs()).clamp(0.0, 1.0),
                            onTap: () => onChanged(i),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavBarButton extends StatelessWidget {
  const _NavBarButton({
    required this.item,
    required this.emphasis,
    required this.onTap,
  });

  final NavItem item;

  /// 0 = 完全未选中，1 = 完全选中。滑动时取中间值。
  final double emphasis;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool selected = emphasis > 0.5;

    final Color color = Color.lerp(
      scheme.onSurface.withValues(alpha: 0.5),
      scheme.primary,
      emphasis,
    )!;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.cardMedium),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(item.icon, size: 22, color: color),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 11,
              height: 1,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
