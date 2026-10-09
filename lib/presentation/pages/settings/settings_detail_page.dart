import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../domain/remote/remote_config.dart';
import '../../../domain/settings/app_theme_mode.dart';
import '../../../domain/settings/class_reminder_settings.dart';
import '../../../domain/settings/motion_settings.dart';
import '../../../domain/settings/reminder_settings.dart';
import '../../../domain/timer/timer_engine.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/class_reminder_provider.dart';
import '../../providers/timer_provider.dart';
import '../../widgets/ambient_background.dart';
import '../../widgets/app_card.dart';
import '../../widgets/motion_scope.dart';
import '../../widgets/pressable.dart';
import 'background_section.dart';

/// 二级「设置」页 —— 从「我的」点进来。
///
/// ## 为什么要拆成两级
///
/// 原来所有控件堆在一页里，一屏放不下、要滚很久才找得到想要的那一项。
/// 拆开后分工：
///   - **「我的」（一级）**：入口列表 —— 设置 / 保活 / 课表 / 关于
///   - **「设置」（二级）**：真正调数值的地方 —— 计时 / 提醒 / 外观 / 背景 / 动效
class SettingsDetailPage extends ConsumerWidget {
  const SettingsDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TimerConfig config = ref.watch(configProvider);
    final TimerConfigNotifier notifier = ref.read(configProvider.notifier);
    final ReminderSettings reminder = ref.watch(reminderSettingsProvider);
    final ReminderSettingsNotifier reminderNotifier =
        ref.read(reminderSettingsProvider.notifier);
    final ClassReminderSettings classReminder =
        ref.watch(classReminderSettingsProvider);
    // 系统有没有放行「精确闹钟」。false 时课表那张卡里插一条提示 ——
    // Android 12 只能用户手动开，不给提示的话提醒会**静默**晚几分钟
    // （对"提前 10 分钟"来说等于没用，所以必须让用户看得见）
    final bool? exactAlarm =
        ref.watch(classReminderExactAlarmProvider).value;
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
                  _Header(onBack: () => Navigator.of(context).maybePop()),
                  const SizedBox(height: AppSpacing.tight),

                  const _SectionLabel('计时'),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: <Widget>[
                        _StepperRow(
                          label: '专注时长',
                          value: config.focusMinutes,
                          unit: '分钟',
                          step: 5,
                          min: 5,
                          max: 120,
                          onChanged: notifier.setFocusMinutes,
                        ),
                        const _RowDivider(),
                        _StepperRow(
                          label: '短休息',
                          value: config.shortBreakMinutes,
                          unit: '分钟',
                          step: 1,
                          min: 1,
                          max: 60,
                          onChanged: notifier.setShortBreakMinutes,
                        ),
                        const _RowDivider(),
                        _StepperRow(
                          label: '长休息',
                          value: config.longBreakMinutes,
                          unit: '分钟',
                          step: 5,
                          min: 5,
                          max: 60,
                          onChanged: notifier.setLongBreakMinutes,
                        ),
                        const _RowDivider(),
                        _StepperRow(
                          label: '长休息间隔',
                          value: config.longBreakInterval,
                          unit: '个番茄',
                          step: 1,
                          min: 2,
                          max: 8,
                          onChanged: notifier.setLongBreakInterval,
                        ),
                        const _RowDivider(),
                        _SwitchRow(
                          label: '自动开始下一阶段',
                          subtitle: '阶段结束后不等你点，直接进入下一段',
                          value: config.autoStartNext,
                          onChanged: notifier.setAutoStartNext,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.section),
                  const _SectionLabel('提醒'),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: <Widget>[
                        _SwitchRow(
                          label: '到点响铃',
                          // 说清语义：关掉 ≠ 不提醒，只是静默
                          subtitle: '关掉后到点只出通知，不响铃不震动',
                          value: reminder.soundEnabled,
                          onChanged: reminderNotifier.setSoundEnabled,
                        ),
                        const _RowDivider(),
                        _SwitchRow(
                          label: '震动',
                          subtitle: '响铃时同时震动',
                          value: reminder.vibrateEnabled,
                          // 总开关关掉时这一项没有意义，置灰
                          enabled: reminder.soundEnabled,
                          onChanged: reminderNotifier.setVibrateEnabled,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.section),
                  const _SectionLabel('课表'),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: <Widget>[
                        _SwitchRow(
                          // ⚠️ 这一行原来叫「上课提醒」，但它绑的是 vibrate ——
                          // 用户想"关掉上课提醒"会关它，可「响铃」还开着、照样响。
                          // 改名跟上面番茄钟那组保持一致（那边就叫「震动」）
                          label: '震动',
                          // 说清"什么时候提醒" —— 用户会问"我导入了怎么没响"
                          subtitle: '每节课上课前 10 分钟提醒，响时震动',
                          value: classReminder.vibrate,
                          onChanged: (bool v) => ref
                              .read(classReminderSettingsProvider.notifier)
                              .setVibrate(v),
                        ),
                        const _RowDivider(),
                        _SwitchRow(
                          label: '响铃',
                          subtitle: '关掉就只震动，不响铃',
                          value: classReminder.sound,
                          onChanged: (bool v) => ref
                              .read(classReminderSettingsProvider.notifier)
                              .setSound(v),
                        ),
                        // 只在"系统没放行精确闹钟"时出现（Android 12 常见）
                        if (exactAlarm == false) ...<Widget>[
                          const _RowDivider(),
                          _ExactAlarmRow(
                            onTap: () => ref
                                .read(classReminderServiceProvider)
                                .openExactAlarmSettings(),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.section),
                  const _SectionLabel('外观'),
                  AppCard(
                    child: Column(
                      children: <Widget>[
                        _ThemeModeRow(
                          value: ref.watch(appThemeModeProvider),
                          onChanged: (AppThemeMode m) =>
                              ref.read(appThemeModeProvider.notifier).set(m),
                        ),
                        const Divider(height: 1, indent: AppSpacing.item, endIndent: AppSpacing.item),
                        _DynamicColorRow(
                          value: ref.watch(dynamicColorProvider),
                          onChanged: (bool v) =>
                              ref.read(dynamicColorProvider.notifier).set(v),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.section),
                  const _SectionLabel('背景'),
                  const BackgroundSection(),

                  const SizedBox(height: AppSpacing.section),
                  const _SectionLabel('动效'),
                  AppCard(
                    child: _MotionRow(
                      value: ref.watch(motionSettingsProvider),
                      // 拖动中只更新界面（不写库），松手才落库一次 —— 见 setScale 注释
                      onChanged: (double v) => ref
                          .read(motionSettingsProvider.notifier)
                          .setScale(v, persist: false),
                      onChangeEnd: (double v) =>
                          ref.read(motionSettingsProvider.notifier).setScale(v),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.section),
                  AppCard(
                    child: Text(
                      '这里的改动会立刻生效并保存。'
                      '计时相关设置只影响「下一次开始」的番茄，'
                      '正在跑的那一个不受影响。',
                      style: text.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                        height: 1.7,
                      ),
                    ),
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

/// 二级页的顶部：返回 + 标题
class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '返回',
        ),
        Expanded(child: Text(t('设置'), style: text.titleLarge)),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: AppSpacing.tight),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

/// 「主题」行：三选一分段控件（跟随系统 / 浅色 / 深色）
class _ThemeModeRow extends StatelessWidget {
  const _ThemeModeRow({required this.value, required this.onChanged});

  final AppThemeMode value;
  final ValueChanged<AppThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.item,
        12,
        AppSpacing.item,
        14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('主题', style: text.bodyMedium),
          const SizedBox(height: 10),
          SegmentedButton<AppThemeMode>(
            segments: AppThemeMode.values
                .map(
                  (AppThemeMode m) => ButtonSegment<AppThemeMode>(
                    value: m,
                    label: Text(m.label),
                  ),
                )
                .toList(),
            selected: <AppThemeMode>{value},
            onSelectionChanged: (Set<AppThemeMode> s) {
              if (s.isNotEmpty) onChanged(s.first);
            },
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

/// 「跟随系统取色」行：开关。
///
/// 默认**关** —— App 叫「一颗番茄」，品牌色就是番茄红/橙。打开后主题色跟着
/// 系统壁纸走（Material You），但同一张截图在不同手机上颜色会不一样。
class _DynamicColorRow extends StatelessWidget {
  const _DynamicColorRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.item),
      title: Text('跟随系统取色', style: text.bodyMedium),
      subtitle: Text(
        value ? '主题色跟着系统壁纸走' : '主题色固定为番茄红',
        style: text.bodySmall?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// 「动效节奏」行：一个滑动条，作用到**全局所有动画**的时长倍率。
///
/// 为什么给用户一个滑动条而不是写死一个"最好看"的时长：
/// 「多慢才叫丝滑」是主观的 —— 与其猜一个值，不如把总闸交出去，默认停在「从容」。
/// 拖动时即时生效（当场能看到整个界面的动效变快/变慢），松手才落库。
class _MotionRow extends StatelessWidget {
  const _MotionRow({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final MotionSettings value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    // 档位名的切换动画也走动效规范 —— 它自己也得是"丝滑"的一部分
    final Motion motion = MotionScope.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.item,
        12,
        AppSpacing.item,
        6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('动效节奏', style: text.bodyMedium)),
              AnimatedSwitcher(
                duration: motion.standard,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (Widget child, Animation<double> a) =>
                    FadeTransition(
                  opacity: a,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.92, end: 1).animate(a),
                    child: child,
                  ),
                ),
                child: Text(
                  value.label,
                  // key 用档位名：只有档位真的变了才触发切换动画
                  key: ValueKey<String>(value.label),
                  style: text.titleMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value.hint,
            style: text.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 2),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: scheme.primary.withValues(alpha: 0.85),
              inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.10),
              thumbColor: scheme.primary,
              overlayColor: scheme.primary.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
            ),
            child: Slider(
              value: value.scale.clamp(
                MotionSettings.minScale,
                MotionSettings.maxScale,
              ),
              min: MotionSettings.minScale,
              max: MotionSettings.maxScale,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text('轻盈', style: _endLabelStyle(scheme, text)),
                Text('悠长', style: _endLabelStyle(scheme, text)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle? _endLabelStyle(ColorScheme scheme, TextTheme text) =>
      text.bodySmall?.copyWith(
        color: scheme.onSurface.withValues(alpha: 0.4),
      );
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

/// 「标签 — 减 值 加」的行
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.unit,
    required this.step,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final String unit;
  final int step;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.item,
        vertical: 10,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: text.bodyMedium)),
          Text(
            '$value',
            style: text.titleMedium?.copyWith(
              color: scheme.primary,
              fontFeatures: const <FontFeature>[FontFeature('tnum')],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            unit,
            style: text.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(width: 8),
          _RoundIconButton(
            icon: Icons.remove_rounded,
            enabled: value > min,
            onTap: () => onChanged((value - step).clamp(min, max)),
          ),
          const SizedBox(width: 6),
          _RoundIconButton(
            icon: Icons.add_rounded,
            enabled: value < max,
            onTap: () => onChanged((value + step).clamp(min, max)),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    // 用 Pressable 而不是 InkWell（水波纹和玻璃语言不合，见其注释）。
    // 小圆按钮带一点缩放，按下去有"陷进去"的实体感。
    return Pressable(
      onTap: enabled ? onTap : null,
      scale: 0.92,
      highlightColor: scheme.onSurface.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: enabled ? 0.07 : 0.03),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 18,
          color: scheme.onSurface.withValues(alpha: enabled ? 0.7 : 0.25),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// 置灰不可点（例如总开关关掉后，"震动"这一项就没有意义了）
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.item,
        8,
        AppSpacing.tight,
        8,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: text.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}

/// 「精确提醒未开启」提示行 —— **只在系统没放行精确闹钟时出现**。
///
/// ## 为什么必须有这一条
///
/// Android 12（API 31/32）只有 `SCHEDULE_EXACT_ALARM`，且**必须用户去系统设置里开**。
/// 拿不到时原生会降级成不精确闹钟（`setAndAllowWhileIdle`），在 Doze 下可能晚
/// 几分钟到十几分钟 —— 而"上课前 10 分钟提醒"晚十几分钟就等于没提醒。
/// 原来这个降级是**完全静默**的：用户只会觉得"这功能不灵"。
///
/// 点一下直接跳到系统的「闹钟与提醒」授权页（`ACTION_REQUEST_SCHEDULE_EXACT_ALARM`）。
class _ExactAlarmRow extends StatelessWidget {
  const _ExactAlarmRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.item,
          10,
          AppSpacing.tight,
          10,
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.alarm_off_rounded, size: 18, color: scheme.error),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('精确提醒未开启', style: text.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    '系统可能让上课提醒晚几分钟。点这里去开启「闹钟与提醒」',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: scheme.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
