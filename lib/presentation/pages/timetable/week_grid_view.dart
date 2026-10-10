import 'package:flutter/material.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/timetable_palette.dart';
import '../../../domain/timetable/course.dart';
import '../../../domain/timetable/period_time.dart';
import '../../../domain/timetable/week_layout.dart';
import '../../widgets/app_card.dart';

// ---------------------------------------------------------------------------
// 版面常量
// ---------------------------------------------------------------------------

/// 每节的行高。58 是权衡：够高，课名 + 教室两行字放得下；又够矮，
/// 10 节不至于让整页翻两屏。
const double _kRowHeight = 58;

/// 午休那一刀的**额外**高度。只比普通行缝高一点点 ——
/// 它要传达的是「这里有一段空档」，不是「这里有一节空课」。
const double _kLunchGap = 16;

/// 左侧节次栏宽度。要放下节次号和「08:00」这种时刻。
const double _kPeriodColumnWidth = 44;

/// 表头（周一…周日）高度
const double _kHeaderHeight = 32;

/// 格子与网格线之间留的缝 —— 让每个格子看起来是"一块"，
/// 而不是和网格线糊在一起。相邻两个格子之间因此有 4px 的缝。
const double _kBlockInset = 2;

/// 周视图网格 —— 经典「节次 × 星期」表，**只读展示**。
///
/// ```
/// ┌──────┬────┬────┬────┬────┬────┐
/// │      │周一│周二│周三│周四│周五│   ← 表头
/// ├──────┼────┼────┼────┼────┼────┤
/// │ 1    │    │高数│    │    │    │
/// │08:00 │    │    │    │    │    │   ← 每节一行，等高
/// │ …    │    │    │    │    │    │
/// │ 午休 │    │    │    │    │    │   ← 午休那一刀（比普通行缝高一点）
/// │ 5    │    │    │    │    │    │
/// │14:00 │    │    │    │    │    │
/// ├──────┴────┴────┴────┴────┴────┤
/// │ 晚自习 19:00~21:30             │   ← 课表外的内容，只画一条时间条
/// └────────────────────────────────┘
/// ```
///
/// ## 为什么每节等高，而不是按真实时间比例
///
/// 按时间比例排的话，午休（一两小时）会变成一大片空白，手机上要滑很久才看得到
/// 下午的课。用户要的是「经典周视图」，经典课表就是每节等高 ——
/// 具体几点，左侧节次栏里写着。
///
/// ## 为什么用 Stack 绝对定位，而不是 Column 做行合并
///
/// 跨节的课（连排两节）必须画成**一整块**。用 Column 就得在父级做 `RowSpan`，
/// Flutter 没有现成的写法；改成绝对定位，`top / height` 一算就自然跨行，
/// 而且**跨午休也不会断**（普通行合并遇到午休那一刀很容易算错）。
///
/// ## 只读
///
/// 这一步只画不点。三点点菜单（临时删除 / 永久删除 / 加课）和改时间是下一步，
/// 所以这里刻意不给格子挂 `onTap` —— 免得点了没反应让人以为是坏的。
class WeekGridView extends StatelessWidget {
  const WeekGridView({
    super.key,
    required this.courses,
    required this.schedule,
    this.onCellMenu,
    this.onEmptyCellMenu,
  });

  final List<Course> courses;
  final TimetableSchedule schedule;

  /// 点了某格右上角的三个点。null = 不显示三个点（纯只读模式，
  /// 组件测试和没接菜单的调用方继续用）。
  final void Function(Course course, Rect anchor)? onCellMenu;

  /// 点了某列的**空白格** —— 加课的入口（空格子上没有三个点可点）。
  final void Function(int weekday, int period, Rect anchor)?
      onEmptyCellMenu;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final List<int> days = weekViewColumns(courses);
    final int periodCount = weekViewPeriodCount(schedule, courses);
    final int? lunchAfter = lunchBreakAfterPeriod(schedule.periods);

    if (periodCount <= 0 || days.isEmpty) return const SizedBox.shrink();

    final double bodyHeight = _yOf(periodCount + 1, lunchAfter);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Header(days: days),
          SizedBox(
            height: bodyHeight,
            child: Row(
              // stretch：让左侧节次栏和右侧网格区拿到**同样的确定高度**。
              // 不 stretch 的话，两边都是"只有定位子项"的 Stack，
              // 在松约束下会塌成 0 高（2026-10-07 写这页时踩到）。
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  width: _kPeriodColumnWidth,
                  child: _PeriodColumn(
                    schedule: schedule,
                    periodCount: periodCount,
                    lunchAfterPeriod: lunchAfter,
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      // 网格线画在最底层，格子盖在上面
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _GridPainter(
                              periodCount: periodCount,
                              dayCount: days.length,
                              lunchAfterPeriod: lunchAfter,
                              lineColor:
                                  scheme.onSurface.withValues(alpha: 0.08),
                              lunchColor:
                                  scheme.onSurface.withValues(alpha: 0.035),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            for (final int day in days)
                              Expanded(
                                child: _DayColumn(
                                  weekday: day,
                                  courses: _coursesOfDay(day),
                                  lunchAfterPeriod: lunchAfter,
                                  periodCount: periodCount,
                                  onCellMenu: onCellMenu,
                                  onEmptyCellMenu: onEmptyCellMenu,
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
          if (schedule.evening != null) ...<Widget>[
            const SizedBox(height: AppSpacing.tight),
            _EveningBar(evening: schedule.evening!),
          ],
        ],
      ),
    );
  }

  List<Course> _coursesOfDay(int day) {
    final List<Course> list = <Course>[
      for (final Course c in courses)
        if (c.weekday == day) c,
    ]..sort((Course a, Course b) => a.startPeriod.compareTo(b.startPeriod));
    return list;
  }
}

/// 第 [period] 节的**顶边** y 坐标（节次从 1 开始）。
///
/// 整个网格的行位置只有这一个公式，所以它必须同时被网格线、左侧节次栏、
/// 课程格子三处共用 —— 各自算一遍迟早会算出不一样的结果。
double _yOf(int period, int? lunchAfterPeriod) {
  double y = (period - 1) * _kRowHeight;
  if (lunchAfterPeriod != null && period > lunchAfterPeriod) {
    y += _kLunchGap;
  }
  return y;
}

// ---------------------------------------------------------------------------
// 表头
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.days});

  final List<int> days;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: _kHeaderHeight,
      child: Row(
        children: <Widget>[
          const SizedBox(width: _kPeriodColumnWidth),
          for (final int day in days)
            Expanded(
              child: Center(
                child: Text(
                  weekdayShort(day),
                  style: text.bodySmall?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 1 → '周一' … 7 → '周日'
String weekdayShort(int weekday) =>
    const <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日']
        [weekday.clamp(1, 7) - 1];

// ---------------------------------------------------------------------------
// 左侧节次栏
// ---------------------------------------------------------------------------

class _PeriodColumn extends StatelessWidget {
  const _PeriodColumn({
    required this.schedule,
    required this.periodCount,
    required this.lunchAfterPeriod,
  });

  final TimetableSchedule schedule;
  final int periodCount;
  final int? lunchAfterPeriod;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // 提到局部：字段（哪怕是 final）不会被 Dart 提升成非空类型，
    // 直接 `lunchAfterPeriod + 1` 会被分析器判为"可能在 null 上做加法"
    final int? lunch = lunchAfterPeriod;

    return Stack(
      children: <Widget>[
        for (int p = 1; p <= periodCount; p++)
          Positioned(
            left: 0,
            right: 0,
            top: _yOf(p, lunch),
            height: _kRowHeight,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '$p',
                    style: text.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                      color: scheme.onSurface.withValues(alpha: 0.7),
                      fontFeatures: const <FontFeature>[FontFeature('tnum')],
                    ),
                  ),
                  if (schedule.forPeriod(p) != null)
                    Text(
                      minutesToLabel(schedule.forPeriod(p)!.startMinute),
                      style: text.bodySmall?.copyWith(
                        fontSize: 9,
                        height: 1.3,
                        color: scheme.onSurface.withValues(alpha: 0.4),
                        fontFeatures: const <FontFeature>[FontFeature('tnum')],
                      ),
                    ),
                ],
              ),
            ),
          ),

        // 午休那一刀在左侧也标一下 —— 光看右边一个空档，
        // 很容易以为"这里漏画了一行"
        if (lunch != null)
          Positioned(
            left: 0,
            right: 0,
            top: _yOf(lunch + 1, lunch),
            height: _kLunchGap,
            child: Center(
              child: Text(
                '午休',
                style: text.bodySmall?.copyWith(
                  fontSize: 8.5,
                  color: scheme.onSurface.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 一天的列
// ---------------------------------------------------------------------------

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.weekday,
    required this.courses,
    required this.lunchAfterPeriod,
    required this.periodCount,
    required this.onCellMenu,
    required this.onEmptyCellMenu,
  });

  /// 这一天是周几（1=周一…）—— 空白格加课要靠它定位，
  /// 不能从 courses 反推（那天可能一节课都没有）
  final int weekday;

  /// 这一天有课的格子，按起节次升序
  final List<Course> courses;
  final int? lunchAfterPeriod;
  final int periodCount;
  final void Function(Course course, Rect anchor)? onCellMenu;
  final void Function(int weekday, int period, Rect anchor)?
      onEmptyCellMenu;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // ---- 空白格的加课入口 ----
        // 空格子上没有三个点可点；把整列的空白区做成可点，
        // 按点的位置算出"是第几节"，菜单里预填。放在最底层，
        // 有课的格子盖在上面，各自的点击优先。
        if (onEmptyCellMenu != null)
          Positioned.fill(
            child: GestureDetector(
              // opaque：没有 child 也要接住空白区的点击；
              // 有课的格子是 Stack 里更靠上的兄弟，命中优先级更高
              behavior: HitTestBehavior.opaque,
              onTapUp: (TapUpDetails d) => _tapEmpty(context, d),
            ),
          ),
        for (final Course c in courses)
          Positioned(
            left: _kBlockInset,
            right: _kBlockInset,
            top: _yOf(c.startPeriod, lunchAfterPeriod) + _kBlockInset,
            height: _blockHeight(c),
            child: _CellContent(
              course: c,
              onMenu: onCellMenu == null
                  ? null
                  : (Rect anchor) => onCellMenu!(c, anchor),
            ),
          ),
      ],
    );
  }

  /// 空白处点击：算出点的是第几节，回调加课。
  /// 点在午休缝 / 晚自习条 / 行距外 → 不响应。
  void _tapEmpty(BuildContext context, TapUpDetails d) {
    final int? period = _periodAtY(d.localPosition.dy);
    if (period == null) return;
    final RenderBox box = context.findRenderObject()! as RenderBox;
    final Offset global = box.localToGlobal(d.localPosition);
    onEmptyCellMenu!(
      weekday,
      period,
      Rect.fromCenter(center: global, width: 48, height: 40),
    );
  }

  /// y → 节次（列内局部坐标）。午休缝不属于任何一节。
  int? _periodAtY(double dy) {
    final int? lunch = lunchAfterPeriod;
    if (lunch != null) {
      final double gapTop = _yOf(lunch + 1, lunch) - _kLunchGap;
      if (dy >= gapTop && dy < _yOf(lunch + 1, lunch)) return null;
    }
    for (int p = 1; p <= periodCount; p++) {
      final double top = _yOf(p, lunchAfterPeriod);
      final double bottom = _yOf(p + 1, lunchAfterPeriod);
      if (dy >= top && dy < bottom) return p;
    }
    return null;
  }

  /// 格子高度 = 它跨的那几行的总高（含中间可能夹着的午休）
  double _blockHeight(Course c) {
    final double top = _yOf(c.startPeriod, lunchAfterPeriod);
    final double bottom = _yOf(c.endPeriod + 1, lunchAfterPeriod);
    // 兜底 18：脏数据（endPeriod 小于 startPeriod）也不该画出一个负高度的框
    final double h = bottom - top - _kBlockInset * 2;
    return h < 18 ? 18 : h;
  }
}

/// 格子内容 + 右上角的三个点。
///
/// 三个点单独一层叠在内容上（而不是塞进 [_CourseBlock] 的 Column）：
/// 蹩脚的布局会挤压课名；独立定位永远在右上角，且点击区域固定。
class _CellContent extends StatelessWidget {
  const _CellContent({required this.course, this.onMenu});

  final Course course;
  final void Function(Rect anchor)? onMenu;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final CourseColor colors = courseColorFor(scheme, course.colorIndex);

    return Stack(
      children: <Widget>[
        Positioned.fill(child: _CourseBlock(course: course)),
        if (onMenu != null)
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                final RenderBox box =
                    context.findRenderObject()! as RenderBox;
                final Offset topLeft = box.localToGlobal(Offset.zero);
                onMenu!(
                  Rect.fromLTWH(
                    topLeft.dx + box.size.width - 26,
                    topLeft.dy,
                    26,
                    22,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
                child: Icon(
                  Icons.more_horiz,
                  size: 14,
                  color: colors.onFill.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 一个课程格子
// ---------------------------------------------------------------------------

class _CourseBlock extends StatelessWidget {
  const _CourseBlock({required this.course});

  final Course course;

  /// 教室名去掉显示用的装饰前缀（`@腾龙楼408教室` → `腾龙楼408教室`）。
  /// 实现见 [courseLocationForDisplay] —— 放在 domain 层是为了能单测。
  static String _displayLocation(String raw) => courseLocationForDisplay(raw);

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final CourseColor colors = courseColorFor(scheme, course.colorIndex);
    final String location = _displayLocation(course.location);
    // 格子越高，能塞的行越多、字号也敢放大
    final bool roomy = course.periodSpan >= 2;
    final bool tall = course.periodSpan >= 3;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Padding(
        // 矮格子（单节）左右也收一点，给文字让出宽度
        padding: EdgeInsets.symmetric(
          horizontal: roomy ? 5 : 3,
          vertical: roomy ? 4 : 2,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 课名：flex 3 —— 空间紧张时优先压缩它（教室信息更"定位"，
            // 用户扫一眼课表主要是想知道"在哪上"）
            Flexible(
              flex: 3,
              child: Text(
                course.name,
                maxLines: tall ? 3 : (roomy ? 2 : 1),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: roomy ? 11.5 : 10,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: colors.onFill,
                ),
              ),
            ),
            // 教室：flex 2，且**多给一行**（用户报"教室显示不全"，
            // 长教室名在窄格子里本来就需要两行才放得下）
            if (location.isNotEmpty)
              Flexible(
                flex: 2,
                child: Text(
                  location,
                  maxLines: roomy ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: roomy ? 9.5 : 8.5,
                    height: 1.25,
                    color: colors.onFill.withValues(alpha: 0.78),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 晚自习
// ---------------------------------------------------------------------------

/// 晚自习在课表图之外，所以**不填课**，只在网格下面标一条时间条。
class _EveningBar extends StatelessWidget {
  const _EveningBar({required this.evening});

  final EveningBlock evening;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.nightlight_outlined,
            size: 14,
            color: scheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 6),
          Text(
            '晚自习',
            style: text.bodySmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const Spacer(),
          Text(
            '${minutesToLabel(evening.startMinute)}'
            '~${minutesToLabel(evening.endMinute)}',
            style: text.bodySmall?.copyWith(
              fontSize: 12,
              color: scheme.onSurface.withValues(alpha: 0.55),
              fontFeatures: const <FontFeature>[FontFeature('tnum')],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 网格线
// ---------------------------------------------------------------------------

/// 只画网格线 + 午休那一层底 —— 格子是独立 widget 叠在上面的。
///
/// 为什么网格线用 `CustomPainter` 而不是给每个格子加 border：
/// 格子是**跨行**的，跨行格子的边框会跟着跨过去，网格线就断了。
/// 网格线属于"背景"，和格子的层级分开画才不会互相干扰。
class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.periodCount,
    required this.dayCount,
    required this.lunchAfterPeriod,
    required this.lineColor,
    required this.lunchColor,
  });

  final int periodCount;
  final int dayCount;
  final int? lunchAfterPeriod;
  final Color lineColor;
  final Color lunchColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = lineColor
      ..strokeWidth = 1;

    // 午休那一段铺一层极淡的底：让人看出"这里是一段空档"，
    // 而不是以为漏画了一行
    final int? lunch = lunchAfterPeriod;
    if (lunch != null) {
      final double top = _yOf(lunch + 1, lunch);
      canvas.drawRect(
        Rect.fromLTWH(0, top, size.width, _kLunchGap),
        Paint()..color = lunchColor,
      );
    }

    // 横向：每节一条线（含首尾两条边）
    for (int p = 1; p <= periodCount + 1; p++) {
      final double y = _yOf(p, lunchAfterPeriod);
      if (y > size.height) continue;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    // 纵向：列分隔线
    final double dayWidth = size.width / dayCount;
    for (int d = 0; d <= dayCount; d++) {
      final double x = d * dayWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.periodCount != periodCount ||
      old.dayCount != dayCount ||
      old.lunchAfterPeriod != lunchAfterPeriod ||
      old.lineColor != lineColor ||
      old.lunchColor != lunchColor;
}
