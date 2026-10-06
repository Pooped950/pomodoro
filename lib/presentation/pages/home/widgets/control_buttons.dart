import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../core/theme/motion_tokens.dart';
import '../../../../domain/timer/timer_state.dart';
import '../../../widgets/glass_primary_button.dart';
import '../../../widgets/motion_scope.dart';

/// 主操作区：一个液态玻璃大按钮 + 两个次要操作。
///
/// 设计意图（方案 5.3 节）：主按钮视觉权重最高、易于拇指触达；
/// 跳过 / 放弃是破坏性较小的操作，用低视觉权重的文字按钮，避免误触。
///
/// ## 主按钮为什么是玻璃（2026-10-05 改）
///
/// 原来是 `FilledButton` 一块纯色，和整个 App 的玻璃语言脱节 ——
/// 背景是流动的环境色光晕，主按钮却是块实心色，像贴上去的。
/// 现在换成 [GlassPrimaryButton]：真高斯模糊 + 方向性高光 + 强调色外发光，
/// 和底部导航条、卡片是同一套材质。
///
/// 次要操作（跳过 / 放弃）**刻意保持纯文字**，不做玻璃 ——
/// 它们需要低视觉权重，做成玻璃反而会跟主按钮抢注意力。
class ControlButtons extends StatelessWidget {
  const ControlButtons({
    super.key,
    required this.phase,
    required this.isIdle,
    required this.isRunning,
    required this.accentColor,
    required this.onToggle,
    required this.onSkip,
    required this.onAbandon,
  });

  final TimerPhase phase;
  final bool isIdle;
  final bool isRunning;
  final Color accentColor;
  final VoidCallback onToggle;
  final VoidCallback onSkip;
  final VoidCallback onAbandon;

  String get _primaryLabel {
    if (isIdle) {
      return phase == TimerPhase.focus ? '开始专注' : '开始休息';
    }
    return isRunning ? '暂停' : '继续';
  }

  IconData get _primaryIcon {
    if (isIdle) return Icons.play_arrow_rounded;
    return isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Motion motion = MotionScope.of(context);

    return Column(
      children: <Widget>[
        SizedBox(
          width: double.infinity,
          child: GlassPrimaryButton(
            // key 跟着"语义"变：从「暂停」变「继续」时重建一次，
            // 避免按下态（缩小）被带到新标签上
            key: ValueKey<String>(_primaryLabel),
            label: _primaryLabel,
            icon: _primaryIcon,
            accent: accentColor,
            onPressed: onToggle,
          ),
        ),

        // 未开始时隐藏次要操作，减少干扰。
        // 用 AnimatedSize 让"多出一排"是长出来的，而不是瞬间跳出来。
        AnimatedSize(
          duration: motion.standard,
          curve: MotionTokens.emphasized,
          alignment: Alignment.topCenter,
          child: isIdle
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.tight),
                  child: AnimatedOpacity(
                    // 先长高度、后显内容：反过来会看到文字在一条缝里被压扁
                    opacity: isIdle ? 0 : 1,
                    duration: motion.standard,
                    curve: Curves.easeOut,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: <Widget>[
                        TextButton.icon(
                          onPressed: onSkip,
                          icon: const Icon(Icons.skip_next_rounded, size: 20),
                          label: Text(
                            phase == TimerPhase.focus ? '跳过专注' : '跳过休息',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: onAbandon,
                          icon: const Icon(Icons.close_rounded, size: 20),
                          label: Text(
                            phase == TimerPhase.focus ? '放弃' : '结束休息',
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor:
                                scheme.onSurface.withValues(alpha: 0.5),
                          ),
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
