import 'package:flutter/material.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../domain/timetable/period_time.dart';
import '../../widgets/app_card.dart';

/// 把当前排出来的时间表给用户看一眼 —— 排错了当场能发现。
///
/// ## 为什么有 [dimmed]（2026-10-07 用户要求）
///
/// 还**没有输入任何东西**时（锚点全是预填的默认值），预览是一份"示意"
/// 而不是用户拍板的结果 —— 整块降透明度，视觉上退成背景；
/// 用户改过任意一项、或粘贴了官方作息表之后，才以正常浓度显示。
class SchedulePreview extends StatelessWidget {
  const SchedulePreview({super.key, required this.schedule, this.dimmed = false});

  final TimetableSchedule? schedule;

  /// true = 还没输入过，整块淡显
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TimetableSchedule? s = schedule;

    if (s == null) {
      return Text(
        '时间还没填完整（格式要像 08:00）',
        style: text.bodySmall?.copyWith(color: scheme.error),
      );
    }

    if (s.isEmpty) return const SizedBox.shrink();

    final Widget card = AppCard(
      padding: const EdgeInsets.all(AppSpacing.item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('排出来是这样', style: text.bodyMedium),
          const SizedBox(height: AppSpacing.tight),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              for (final PeriodTime p in s.periods)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(
                    '${p.period}·${minutesToLabel(p.startMinute)}'
                    '-${minutesToLabel(p.endMinute)}',
                    style: text.bodySmall?.copyWith(
                      color: scheme.primary,
                      fontFeatures: const <FontFeature>[FontFeature('tnum')],
                    ),
                  ),
                ),
            ],
          ),
          if (s.evening != null) ...<Widget>[
            const SizedBox(height: AppSpacing.tight),
            Text(
              '晚自习 ${minutesToLabel(s.evening!.startMinute)}'
              '~${minutesToLabel(s.evening!.endMinute)}',
              style: text.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );

    if (!dimmed) return card;

    return Opacity(
      opacity: 0.45,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          card,
          const SizedBox(height: AppSpacing.tight),
          Text(
            '这是预填默认值的示意 —— 改上面任意一项或粘贴作息表后会变',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
