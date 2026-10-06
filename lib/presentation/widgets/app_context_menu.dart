import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/theme/motion_tokens.dart';
import 'glass_surface.dart';
import 'motion_scope.dart';
import 'pressable.dart';

/// 上下文菜单里的一项
@immutable
class AppContextMenuItem<T> {
  const AppContextMenuItem({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData icon;

  /// 破坏性操作（删除）—— 用 error 色，和普通操作在**颜色**上就能区分开
  final bool destructive;
}

/// **贴住触发元素**弹出的上下文菜单。
///
/// ## 为什么不是底部弹层（2026-10-06 改回来）
///
/// 上一版改成了底部玻璃弹层，用户实测反馈：
/// 「任务页点击三个点以后的弹窗理应是在三个点附近弹出而非下方弹出」。
///
/// 他说得对 —— 底部弹层适合**选择类**操作（任务选择器那种一列可选项），
/// 而"编辑 / 删除这一条"是**针对刚点的那个元素**的动作。动作菜单跑到底部，
/// 手指和视线都要跨越整个屏幕，而且看不出"这个菜单属于哪一条"。
/// 上下文菜单的通用语义就是**在触发点旁边**出现。
///
/// ## 但"丝滑"要保住
///
/// 用户最初的要求是「不要现在这样直白的出来」（指 `PopupMenuButton` 的瞬弹）。
/// 所以这里不用 `PopupMenuButton`，而是自己画：
///   - 从**锚点那个角**缩放展开（不是从中心）—— 视觉上就是"从按钮里长出来"
///   - 淡入 + 轻微上浮
///   - 时长与曲线走动效规范（用户在设置里调「动效节奏」这里跟着变）
///   - 玻璃材质，和 App 其它玻璃是同一套语言
///   - 退场比进场快（`Motion.press` 量级）—— 菜单收回去不该拖泥带水
///
/// ## 位置
///
/// 默认贴在锚点**下方、右对齐**（因为「三个点」通常在行的右端）。
/// 下方放不下就翻到上方；左右会被夹进安全区，不会跑出屏幕。
Future<T?> showAppContextMenu<T>({
  required BuildContext context,
  required Rect anchor,
  required List<AppContextMenuItem<T>> items,
  double width = 172,
}) {
  final Motion motion = MotionScope.resolve(context);
  final MediaQueryData mq = MediaQuery.of(context);

  final _MenuPlacement placement = _MenuPlacement.compute(
    anchor: anchor,
    itemCount: items.length,
    width: width,
    screen: mq.size,
    padding: mq.padding,
  );

  return Navigator.of(context).push<T>(
    _ContextMenuRoute<T>(
      anchor: anchor,
      items: items,
      width: width,
      placement: placement,
      motion: motion,
    ),
  );
}

/// 菜单该摆在哪儿 —— 抽成值对象是为了能在 `buildPage` 与 `buildTransitions`
/// 里共用同一个结果（缩放的原点必须和实际位置一致，否则会"从奇怪的方向长出来"）
@immutable
class _MenuPlacement {
  const _MenuPlacement({
    required this.left,
    required this.top,
    required this.height,
    required this.below,
  });

  final double left;
  final double top;
  final double height;

  /// true = 在锚点下方；false = 翻到了上方
  final bool below;

  /// 菜单内边距（上下各 4）
  static const double _pad = 4;

  /// 每项高度
  static const double itemHeight = 44;

  /// 与锚点的间距
  static const double gap = 6;

  static _MenuPlacement compute({
    required Rect anchor,
    required int itemCount,
    required double width,
    required Size screen,
    required EdgeInsets padding,
  }) {
    final double height = itemCount * itemHeight + _pad * 2;

    // 水平：右边缘对齐锚点右边缘（「三个点」在行右端），再夹进安全区
    double left = anchor.right - width;
    final double minLeft = padding.left + 8;
    final double maxLeft = screen.width - padding.right - 8 - width;
    if (left > maxLeft) left = maxLeft;
    if (left < minLeft) left = minLeft;

    // 垂直：优先下方，放不下就翻到上方
    final double belowTop = anchor.bottom + gap;
    final double aboveTop = anchor.top - gap - height;
    final double bottomLimit = screen.height - padding.bottom - 8;

    final bool below = belowTop + height <= bottomLimit;
    double top = below ? belowTop : aboveTop;

    final double minTop = padding.top + 8;
    if (top + height > bottomLimit) top = bottomLimit - height;
    if (top < minTop) top = minTop;

    return _MenuPlacement(
      left: left,
      top: top,
      height: height,
      below: below,
    );
  }

  /// 缩放原点：从锚点那一侧的角长出来
  Alignment get scaleOrigin =>
      below ? Alignment.topRight : Alignment.bottomRight;
}

/// 自定义 `PopupRoute`（**不用** `RawDialogRoute`）。
///
/// 为什么不用 `showGeneralDialog`：`RawDialogRoute.buildPage` 会把内容包进
/// `SafeArea`，于是"屏幕坐标"就变成了"安全区坐标"，锚点的全局坐标没法直接用。
/// `PopupRoute` 的 `buildPage` 是原样放置的，坐标系统一，算位置才可靠。
class _ContextMenuRoute<T> extends PopupRoute<T> {
  _ContextMenuRoute({
    required this.anchor,
    required this.items,
    required this.width,
    required this.placement,
    required this.motion,
  });

  final Rect anchor;
  final List<AppContextMenuItem<T>> items;
  final double width;
  final _MenuPlacement placement;
  final Motion motion;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.10);

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => '关闭菜单';

  @override
  Duration get transitionDuration => motion.standard;

  /// 退场比进场快：菜单收回去不该拖泥带水
  @override
  Duration get reverseTransitionDuration => motion.press;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _ContextMenuOverlay<T>(
      items: items,
      width: width,
      placement: placement,
      onSelected: (T value) => Navigator.of(context).pop(value),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Animation<double> curved = CurvedAnimation(
      parent: animation,
      curve: MotionTokens.emphasized,
      reverseCurve: MotionTokens.emphasizedIn,
    );

    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        // 透明度比缩放先到位，避免"已经展开完了还在淡入"
        curve: const Interval(0, 0.5, curve: Curves.easeOut),
      ),
      child: ScaleTransition(
        // 从锚点那一侧的角展开 —— 视觉上像"从按钮里长出来"，
        // 而不是从菜单自己的中心"啪"地弹开
        alignment: placement.scaleOrigin,
        scale: Tween<double>(begin: 0.82, end: 1).animate(curved),
        child: child,
      ),
    );
  }
}

class _ContextMenuOverlay<T> extends StatelessWidget {
  const _ContextMenuOverlay({
    required this.items,
    required this.width,
    required this.placement,
    required this.onSelected,
  });

  final List<AppContextMenuItem<T>> items;
  final double width;
  final _MenuPlacement placement;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned(
          left: placement.left,
          top: placement.top,
          width: width,
          child: GlassSurface(
            radius: AppRadius.cardMedium,
            blur: GlassTokens.blur,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final AppContextMenuItem<T> item in items)
                    _ContextMenuItemTile<T>(
                      item: item,
                      onTap: () => onSelected(item.value),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ContextMenuItemTile<T> extends StatelessWidget {
  const _ContextMenuItemTile({required this.item, required this.onTap});

  final AppContextMenuItem<T> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final Color tint = item.destructive ? scheme.error : scheme.onSurface;

    return Pressable(
      onTap: onTap,
      highlightColor: (item.destructive ? scheme.error : scheme.primary)
          .withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: SizedBox(
        height: _MenuPlacement.itemHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: <Widget>[
              Icon(item.icon, size: 18, color: tint),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    color: tint,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
