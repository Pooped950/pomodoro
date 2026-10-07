import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/theme/motion_tokens.dart';
import 'motion_scope.dart';
import 'pressable.dart';

/// 顶部小标签切换器（分段控件）—— 第二页「任务 / 统计」用它。
///
/// ## 为什么自己画，不用 Material 的 `SegmentedButton`
///
/// 设置页那个三选一的 `SegmentedButton` 是**表单里**的控件，直角 + 描边，
/// 站在一堆设置项中间不违和。但这一颗是**页面级**的切换，位置在内容区顶部、
/// 和底部导航条首尾呼应，用 Material 那套会立刻露出"这不是这个 App 的东西"。
///
/// 所以这里改成**一块滑动的药丸指示器**，和 `FloatingNavBar` 是同一套视觉语言：
///   - 选中态是一块圆角药丸，切标签时**滑过去**，不是硬切
///   - 文字颜色跟着插值，不是瞬间变色
///   - 时长与曲线全部走动效规范（用户在设置里调「动效节奏」，这里跟着变）
///
/// ## 为什么不用 `GlassSurface`
///
/// 玻璃靠 `BackdropFilter` 模糊**背后**的内容才成立（见 `GlassSurface` 的注释：
/// "玻璃只有在背后有东西时才看得出来"）。这个控件固定在内容区**上方**，
/// 背后只有环境色背景 —— 用玻璃等于白付一次高斯模糊，观感还更糊。
/// 所以用 `elevatedSurface()` 做一层"抬升表面"，干净且不浪费性能。
class AppSegmentedTabs extends StatelessWidget {
  const AppSegmentedTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  /// 标签文字，顺序即顺序
  final List<String> labels;

  /// 当前选中的下标
  final int index;

  final ValueChanged<int> onChanged;

  /// 控件总高
  static const double height = 40;

  /// 药丸与外壳之间的内缩
  static const double _inset = 3;

  /// 单段最小宽度 —— 太小了"任务"两个字会挤，太大又显得空
  static const double _minSegmentWidth = 76;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Motion motion = MotionScope.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    final double totalWidth =
        labels.length * _minSegmentWidth + _inset * 2;

    return SizedBox(
      width: totalWidth,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: elevatedSurface(scheme, 0.05),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.all(_inset),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double itemWidth = c.maxWidth / labels.length;

              return Stack(
                children: <Widget>[
                  // 滑动指示器：用 AnimatedPositioned 而不是 AnimatedAlign ——
                  // 这里要的是"从上一格滑到下一格"，位置本身就是连续的，
                  // 交给 AnimatedPositioned 插值最直接。
                  AnimatedPositioned(
                    duration: motion.standard,
                    curve: MotionTokens.emphasized,
                    left: index * itemWidth,
                    top: 0,
                    bottom: 0,
                    width: itemWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),

                  Row(
                    children: <Widget>[
                      for (int i = 0; i < labels.length; i++)
                        Expanded(
                          child: Pressable(
                            onTap: () => onChanged(i),
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                            highlightColor:
                                scheme.onSurface.withValues(alpha: 0.06),
                            child: Center(
                              // 文字颜色跟着指示器一起过渡，避免"药丸滑过去了、
                              // 字还是啪地一下换色"
                              child: AnimatedDefaultTextStyle(
                                duration: motion.standard,
                                curve: MotionTokens.soft,
                                style: (text.labelLarge ?? const TextStyle())
                                    .copyWith(
                                  fontSize: 13.5,
                                  fontWeight: i == index
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: i == index
                                      ? scheme.primary
                                      : scheme.onSurface
                                          .withValues(alpha: 0.55),
                                ),
                                child: Text(labels[i]),
                              ),
                            ),
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
