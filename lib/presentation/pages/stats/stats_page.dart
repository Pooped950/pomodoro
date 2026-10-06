import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/motion_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/stats/stats_summary.dart';
import '../../providers/stats_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/motion_scope.dart';

/// 统计页 —— M5-③
///
/// 「看清楚自己的专注习惯」。三块内容：
///   1. 今日概览：专注时长 / 完成番茄 / 休息时长
///   2. 近 7 天专注柱状图
///   3. 近 7 天任务分布
///
/// ## 数据全部从 `sessions` 实时聚合，不建统计表
///
/// 这是方案既定决策。好处是口径只有一处（`domain/stats/stats_summary.dart`），
/// 改了规则历史数据自动按新口径重算，不会出现"统计表和明细对不上"。
///
/// ## 为什么窗口是 7 天
///
/// `sessions` 会随使用无限增长，每次进页面全表扫会越来越慢。
/// 7 天既能回答"我最近怎么样"，查询量又恒定。
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<StatsData> async = ref.watch(statsProvider);
    final TextTheme text = Theme.of(context).textTheme;
    final DateTime now = DateTime.now();

    // 首次加载（还没有任何数据）时才显示骨架，避免"先闪一下空状态再跳成数据"。
    // 注意用 `.value == null` 而不是 `!hasValue`：刷新期间旧数据会被保留，
    // 那时不该退回去显示骨架。
    final StatsData? loaded = async.value;
    final bool firstLoad = async.isLoading && loaded == null;
    final StatsData data = loaded ?? StatsData.empty;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(statsProvider);
              // 等新数据回来，下拉的转圈才会在数据就绪时收起来
              await ref.read(statsProvider.future);
            },
            child: ListView(
              // 内容不满一屏时也要能下拉刷新
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.tight,
                AppSpacing.page,
                kBottomNavSpace,
              ),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child: Text('统计', style: text.titleLarge)),
                    IconButton(
                      onPressed: () => ref.invalidate(statsProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: '刷新',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.tight),

                if (firstLoad)
                  const _Skeleton()
                else if (data.isEmpty)
                  const _EmptyStats()
                else ...<Widget>[
                  FadeSlideIn(
                    index: 0,
                    child: _OverviewCard(data: data, now: now),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  FadeSlideIn(
                    index: 1,
                    child: _WeekChartCard(data: data),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  FadeSlideIn(
                    index: 2,
                    child: _TaskDistributionCard(data: data),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 今日概览
// ---------------------------------------------------------------------

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.data, required this.now});

  final StatsData data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final DayOverview o = data.today;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('今天', style: text.titleMedium),
              const Spacer(),
              Text(
                monthDayLabel(now),
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.item),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _Metric(
                  value: formatDurationHuman(o.focusSeconds),
                  label: '专注时长',
                  color: scheme.primary,
                ),
              ),
              Expanded(
                child: _Metric(
                  value: '${o.completedPomodoros}',
                  unit: '个',
                  label: '完成番茄',
                  color: scheme.primary,
                ),
              ),
              Expanded(
                child: _Metric(
                  value: formatDurationHuman(o.breakSeconds),
                  label: '休息时长',
                  color: scheme.tertiary,
                ),
              ),
            ],
          ),

          if (o.focusSessionCount > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.item),
            Divider(
              height: 1,
              color: scheme.onSurface.withValues(alpha: 0.06),
            ),
            const SizedBox(height: 10),
            Text(
              '平均每次 ${formatDurationHuman(o.averageFocusSeconds)}'
              ' · 完成率 ${(o.completionRate * 100).round()}%'
              '${o.abandonedCount > 0 ? ' · 跳过 ${o.abandonedCount} 次' : ''}',
              style: text.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    required this.color,
    this.unit,
  });

  final String value;
  final String? unit;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                  // 等宽数字：数值变化时宽度不跳
                  fontFeatures: const <FontFeature>[FontFeature('tnum')],
                ),
              ),
            ),
            if (unit != null)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  unit!,
                  style: text.bodySmall?.copyWith(
                    color: color.withValues(alpha: 0.75),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: text.bodySmall?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// 近 7 天柱状图
// ---------------------------------------------------------------------

class _WeekChartCard extends StatelessWidget {
  const _WeekChartCard({required this.data});

  final StatsData data;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final DateTime today = DateTime.now();

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text('近 $kStatsWindowDays 天专注', style: text.titleMedium),
              const Spacer(),
              Text(
                formatDurationHuman(data.weekTotalSeconds),
                style: text.titleMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const <FontFeature>[FontFeature('tnum')],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '合计',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.item),

          SizedBox(
            height: 156,
            child: _WeekBarChart(series: data.week, today: today),
          ),
        ],
      ),
    );
  }
}

/// 柱状图本体：柱子长出来的时候带动画，每根略微错开。
///
/// 为什么自己画而不用现成图表库：整个 App 只有这一处图表，
/// 引一个库要多几百 KB 体积和一套需要对齐的设计语言；
/// 而这里要的东西（圆角柱、今天高亮、生长动画）用 CustomPainter 几十行就够。
class _WeekBarChart extends StatefulWidget {
  const _WeekBarChart({required this.series, required this.today});

  final List<DailyFocus> series;
  final DateTime today;

  @override
  State<_WeekBarChart> createState() => _WeekBarChartState();
}

class _WeekBarChartState extends State<_WeekBarChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionTokens.standard,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // 时长跟随全局动效节奏设置
    _controller.duration = MotionScope.of(context).standard;
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _WeekBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数据变了（下拉刷新 / 新增了记录）就重新长一遍，
    // 否则用户看不出"数字变了"
    if (!_sameSeries(oldWidget.series, widget.series)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? _) {
        return CustomPaint(
          size: Size.infinite,
          painter: _WeekBarPainter(
            series: widget.series,
            today: widget.today,
            t: Curves.easeOutCubic.transform(_controller.value),
            barColor: scheme.primary,
            trackColor: scheme.onSurface.withValues(alpha: 0.05),
            labelColor: scheme.onSurface.withValues(alpha: 0.45),
            todayLabelColor: scheme.primary,
            labelStyle: text.bodySmall?.copyWith(
              fontSize: 10,
              height: 1,
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        );
      },
    );
  }
}

class _WeekBarPainter extends CustomPainter {
  _WeekBarPainter({
    required this.series,
    required this.today,
    required this.t,
    required this.barColor,
    required this.trackColor,
    required this.labelColor,
    required this.todayLabelColor,
    required this.labelStyle,
  });

  final List<DailyFocus> series;
  final DateTime today;

  /// 0 → 1 的全局进度
  final double t;

  final Color barColor;
  final Color trackColor;
  final Color labelColor;
  final Color todayLabelColor;
  final TextStyle? labelStyle;

  /// 顶部给数值标签留的高度
  static const double _topPad = 20;

  /// 底部给「周几」标签留的高度
  static const double _bottomPad = 22;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;

    final int n = series.length;
    final double slot = size.width / n;
    final double barWidth = slot * 0.42;
    final double chartBottom = size.height - _bottomPad;
    final double chartHeight = chartBottom - _topPad;
    if (chartHeight <= 0) return;

    final int maxSeconds = maxFocusSeconds(series);

    for (int i = 0; i < n; i++) {
      final DailyFocus d = series[i];
      final bool isToday = isSameDay(d.day, today);

      final double centerX = slot * (i + 0.5);
      final double left = centerX - barWidth / 2;
      final double right = centerX + barWidth / 2;

      // 底槽：让"没数据的那天"也看得见位置，不至于横轴缺一块
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(left, _topPad, right, chartBottom),
          topLeft: const Radius.circular(7),
          topRight: const Radius.circular(7),
        ),
        Paint()..color = trackColor,
      );

      // 每根柱子错开一点出发，视觉上有"依次长出来"的层次
      final double local = _localProgress(t, i, n);
      final double fullHeight = maxSeconds == 0
          ? 0
          : (d.focusSeconds / maxSeconds) * chartHeight;
      final double h = fullHeight * local;

      if (d.focusSeconds <= 0) {
        // 完全没数据：只画一小段"地平线"，表示这天存在但为 0
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(left, chartBottom - 3, right, chartBottom),
            const Radius.circular(2),
          ),
          Paint()..color = labelColor.withValues(alpha: 0.28),
        );
      } else {
        final Rect barRect =
            Rect.fromLTRB(left, chartBottom - h, right, chartBottom);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            barRect,
            topLeft: const Radius.circular(7),
            topRight: const Radius.circular(7),
          ),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                barColor.withValues(alpha: isToday ? 1.0 : 0.55),
                barColor.withValues(alpha: isToday ? 0.72 : 0.30),
              ],
            ).createShader(barRect),
        );

        // 数值标签：跟着柱子一起淡入，柱子还没长起来时不画（否则数字飘在空中）
        if (local > 0.55) {
          _drawText(
            canvas,
            _compactDuration(d.focusSeconds),
            centerX,
            chartBottom - h - 4,
            labelStyle?.copyWith(
              color: isToday
                  ? todayLabelColor
                  : labelColor,
              fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
            ),
            opacity: ((local - 0.55) / 0.45).clamp(0.0, 1.0),
          );
        }
      }

      // 横轴「周几」
      _drawText(
        canvas,
        weekdayShort(d.day),
        centerX,
        size.height - 8,
        labelStyle?.copyWith(
          color: isToday ? todayLabelColor : labelColor,
          fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
        ),
      );
    }
  }

  /// 第 i 根的局部进度：整体 [t] 上叠一个与序号相关的延迟。
  static double _localProgress(double t, int i, int n) {
    const double step = 0.055;
    final double totalStagger = step * (n - 1);
    final double span = 1 - totalStagger;
    if (span <= 0) return t;
    return ((t - step * i) / span).clamp(0.0, 1.0);
  }

  /// 柱状图上的紧凑时长：`45m` / `2h15`。
  /// 不直接用 `formatDurationHuman` —— 它给的 `2h 15m` 在 7 根柱子下会互相挤。
  static String _compactDuration(int seconds) {
    final int minutes = seconds ~/ 60;
    if (minutes <= 0) return '';
    if (minutes < 60) return '${minutes}m';
    final int h = minutes ~/ 60;
    final int m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h$m';
  }

  /// 在 ([x], [baselineY]) 处居中画一段文字。[opacity] < 1 时淡入。
  void _drawText(
    Canvas canvas,
    String value,
    double x,
    double baselineY,
    TextStyle? style, {
    double opacity = 1,
  }) {
    if (value.isEmpty || style == null) return;

    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: value,
        style: opacity >= 1
            ? style
            : style.copyWith(
                color: style.color?.withValues(alpha: opacity),
              ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, Offset(x - tp.width / 2, baselineY - tp.height));
  }

  @override
  bool shouldRepaint(covariant _WeekBarPainter old) =>
      old.t != t ||
      old.barColor != barColor ||
      old.trackColor != trackColor ||
      old.labelColor != labelColor ||
      old.todayLabelColor != todayLabelColor ||
      !_sameSeries(old.series, series);
}

bool _sameSeries(List<DailyFocus> a, List<DailyFocus> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------
// 任务分布
// ---------------------------------------------------------------------

class _TaskDistributionCard extends StatelessWidget {
  const _TaskDistributionCard({required this.data});

  final StatsData data;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    if (data.tasks.isEmpty) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('近 $kStatsWindowDays 天任务分布', style: text.titleMedium),
            const SizedBox(height: AppSpacing.tight),
            Text(
              '这 7 天还没有专注记录。开始一个番茄并绑定任务，'
              '这里就能看出时间花在了哪些事情上。',
              style: text.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.55),
                height: 1.6,
              ),
            ),
          ],
        ),
      );
    }

    int maxSlice = 0;
    for (final TaskSlice s in data.tasks) {
      if (s.focusSeconds > maxSlice) maxSlice = s.focusSeconds;
    }

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('近 $kStatsWindowDays 天任务分布', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            '专注时长都花在了哪些任务上',
            style: text.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: AppSpacing.item),

          for (int i = 0; i < data.tasks.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == data.tasks.length - 1 ? 0 : AppSpacing.item,
              ),
              child: FadeSlideIn(
                index: i,
                offsetY: 10,
                child: _TaskSliceRow(
                  slice: data.tasks[i],
                  maxSeconds: maxSlice,
                  weekTotal: data.weekTotalSeconds,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskSliceRow extends StatelessWidget {
  const _TaskSliceRow({
    required this.slice,
    required this.maxSeconds,
    required this.weekTotal,
  });

  final TaskSlice slice;
  final int maxSeconds;
  final int weekTotal;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    // 条形长度按"最大的一项占满"来归一 —— 否则全部都很短，看不出差异。
    // 精确占比由右边的百分比文字给出，两者分工：条形看相对高低，数字看准确比例。
    final double factor =
        maxSeconds <= 0 ? 0 : slice.focusSeconds / maxSeconds;
    final int percent =
        weekTotal <= 0 ? 0 : (slice.focusSeconds / weekTotal * 100).round();

    final bool unbound = slice.taskId == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              unbound ? Icons.link_off_rounded : Icons.check_circle_outline,
              size: 15,
              color: scheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                slice.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(
                    alpha: unbound ? 0.6 : 0.92,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatDurationHuman(slice.focusSeconds),
              style: text.bodySmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
                fontFeatures: const <FontFeature>[FontFeature('tnum')],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 34,
              child: Text(
                '$percent%',
                textAlign: TextAlign.right,
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.45),
                  fontFeatures: const <FontFeature>[FontFeature('tnum')],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: SizedBox(
            height: 7,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: ColoredBox(
                    color: scheme.onSurface.withValues(alpha: 0.06),
                  ),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: factor),
                  duration: MotionScope.of(context).standard,
                  curve: MotionTokens.emphasized,
                  builder: (BuildContext context, double v, Widget? _) {
                    return FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: v.clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              scheme.primary.withValues(alpha: 0.85),
                              scheme.primary.withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        if (slice.completedPomodoros > 0)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              '${slice.completedPomodoros} 个番茄',
              style: text.bodySmall?.copyWith(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// 空态 / 骨架
// ---------------------------------------------------------------------

class _EmptyStats extends StatelessWidget {
  const _EmptyStats();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(Icons.insights_rounded, color: scheme.primary, size: 24),
          ),
          const SizedBox(height: AppSpacing.item),
          Text('还没有可统计的数据', style: text.titleMedium),
          const SizedBox(height: AppSpacing.tight),
          Text(
            '跑完第一个番茄后，这里会显示你的专注时长、'
            '近 $kStatsWindowDays 天的趋势，以及时间花在了哪些任务上。'
            '所有数据都来自本机记录，不上传。',
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.6),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// 首次加载时的占位 —— 只是几块淡色矩形，不做花哨的微光动画
/// （统计查询是本机 SQLite，通常几十毫秒就回来了，动画反而会更像"卡了一下"）。
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color c = scheme.onSurface.withValues(alpha: 0.06);

    return Column(
      children: <Widget>[
        for (final double h in <double>[150, 220, 200]) ...<Widget>[
          AppCard(
            child: Container(
              height: h,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.section),
        ],
      ],
    );
  }
}
