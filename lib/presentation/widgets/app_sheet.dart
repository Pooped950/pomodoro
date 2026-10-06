import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/theme/motion_tokens.dart';
import 'glass_surface.dart';
import 'motion_scope.dart';
import 'pressable.dart';

/// 统一的**玻璃底部弹层**。
///
/// ## 为什么不用裸的 `showModalBottomSheet`
///
/// 用户的原话：「点击三个点以后我要以丝滑的滑动补帧跳出来删除和编辑的页面，
/// 而不是现在这样直白的出来」。
///
/// 原来的做法是 `PopupMenuButton` —— 菜单在**点击位置旁边**瞬间弹出，
/// 没有过程、没有材质、和 App 的玻璃语言也无关。现在统一改成：
///   - 从**屏幕底部**滑上来（有明确的来向，用户知道它从哪来、会回哪去）
///   - 玻璃材质，和卡片、导航条同一套语言
///   - 时长与曲线**走动效规范**，用户在设置里调"动效节奏"这里跟着变
///   - 出场带**轻微回弹**（[MotionTokens.overshoot]）——
///     像一块板子被甩上来稳住，而不是匀速平移到位
///
/// ## 为什么用 `sheetAnimationStyle` 而不是自己造 `AnimationController`
///
/// 自己造要拿一个 `vsync`（就得引入 StatefulWidget），
/// 而这个弹层本身是无状态的、内容也各不相同 —— 为了"换一组时长"引入
/// 一个有状态外壳不划算。`AnimationStyle` 正好就是为这个场景加的。
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
}) {
  final Motion motion = MotionScope.resolve(context);

  return showModalBottomSheet<T>(
    context: context,
    // 允许超过默认的"半屏"高度（任务选择器列表长了要能滚）
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    // 遮罩比默认的 black54 淡一些：玻璃弹层不需要那么重的压暗
    barrierColor: Colors.black.withValues(alpha: 0.28),
    sheetAnimationStyle: AnimationStyle(
      duration: motion.sheetEnter,
      reverseDuration: motion.sheetExit,
      // 出场轻微回弹 —— "被甩上来"的实体感
      curve: MotionTokens.overshoot,
      // 收回时快起慢走，干脆利落（退场不该拖）
      reverseCurve: MotionTokens.emphasizedIn,
    ),
    builder: (BuildContext sheetContext) => _SheetSurface(
      child: Builder(builder: builder),
    ),
  );
}

/// 弹层的玻璃外壳 + 四周留白。
///
/// 做成**悬浮**（四周留边）而不是贴边通栏，是为了和底部悬浮导航条一致 ——
/// 通栏弹层看起来像系统默认的 BottomSheet，悬浮的才像这个 App 的东西。
class _SheetSurface extends StatelessWidget {
  const _SheetSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    final double margin = AppSpacing.tight;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        margin,
        0,
        margin,
        (bottomInset > margin ? bottomInset : margin) + margin / 2,
      ),
      child: GlassSurface(
        radius: AppRadius.card,
        blur: GlassTokens.blur,
        child: child,
      ),
    );
  }
}

/// 弹层内容的标准骨架：拖拽把手 +（可选）标题 + 内容。
///
/// 让调用方自己持有这个 `Column`（而不是由 [showAppSheet] 包一层），
/// 是为了避免"Column 里套 Column 再套 Flexible"导致的
/// **无界高度 + flex** 经典报错 —— 调用方要放滚动列表时，
/// 直接把 `Flexible(child: ListView(shrinkWrap: true))` 放进 [children] 即可。
class AppSheetScaffold extends StatelessWidget {
  const AppSheetScaffold({
    super.key,
    required this.children,
    this.title,
    this.subtitle,
  });

  final List<Widget> children;

  /// 弹层标题（如「写方案」）。不传则不占位。
  final String? title;

  /// 标题下方的补充说明
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _DragHandle(),

        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.item,
              0,
              AppSpacing.item,
              AppSpacing.tight,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium,
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),

        ...children,

        const SizedBox(height: AppSpacing.tight),
      ],
    );
  }
}

/// 弹层里的一个操作项：图标 + 标题（+ 可选说明）。
///
/// [destructive] 为 true 时用 error 色（删除这类不可逆操作）——
/// 破坏性操作必须和普通操作在**颜色**上就能区分开，
/// 只靠文字差别在快速操作时容易点错。
class SheetActionTile extends StatelessWidget {
  const SheetActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final Color tint = destructive ? scheme.error : scheme.primary;

    return Pressable(
      onTap: onTap,
      highlightColor: tint.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppRadius.cardMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.item,
          vertical: 11,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Icon(icon, size: 19, color: tint),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: text.bodyMedium?.copyWith(
                      color: destructive ? scheme.error : scheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部那条小横杠 —— 弹层的"抓手"。
///
/// 它的作用不是好看，而是**告诉用户这个面板可以被划走**。
/// 没有它的话，弹层看起来像一个固定的面板，用户不会想到去下拉关闭。
class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        width: 38,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 12),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    );
  }
}
