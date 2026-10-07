/// 周视图的**版面计算** —— 纯函数，宿主机可直接单测。
///
/// 「画哪几列 / 画哪几行 / 午休切在哪两节之间」这三件事都是**算出来的**，
/// 不是画出来的。算错了整张网格都会歪（列宽、行高、格子位置全跟着错），
/// 所以单独放领域层、单独钉测试 —— 而不是埋在 `CustomPainter` 里。
library;

import 'course.dart';
import 'period_time.dart';

/// 周视图要画哪几列 —— 从周一排到「最后一个有课的日子」。
///
/// ## 为什么不固定画 7 列
///
/// 手机屏宽就那么多：7 列的话每列只剩 50 出头像素，一个四字课名就得换行两次。
/// 绝大多数人的课表集中在周一到周五，按实际用到的天数画，每列能宽出四成。
/// 周末有课就自动多一列，**不用改代码**。
///
/// ## 为什么不是"只画有课的那几天"
///
/// 那样周二会凭空消失，网格看起来是**断的** —— 一眼看不出"周二就是没课"。
/// 连着排到最后一个有课的日子，才像一张课表。
///
/// 完全没课时返回周一~周五，让空网格也有个合理形状。
List<int> weekViewColumns(Iterable<Course> courses) {
  int last = 0;
  for (final Course c in courses) {
    if (c.weekday > last) last = c.weekday;
  }
  if (last <= 0) last = 5;
  return <int>[for (int d = 1; d <= last; d++) d];
}

/// 网格要画多少行。
///
/// 取「节次表长度」和「课程实际用到的最大节次」的**较大值** ——
/// 导入时如果时间锚点填少了（节次表排到第 6 节就完了），
/// 第 7、8 节的课不能被裁掉；宁可多画一行空的。
int weekViewPeriodCount(TimetableSchedule schedule, Iterable<Course> courses) {
  int count = schedule.periods.length;
  for (final Course c in courses) {
    if (c.endPeriod > count) count = c.endPeriod;
  }
  return count;
}

/// 午休落在哪两节之间 —— 返回「上午最后一节的节次号」，认不出来返回 null。
///
/// ## 判据
///
/// 和 [morningPeriodCountFromAnchors] 同一个思路：最大的那个间隔要**明显大于**
/// 中位间隔才认。区别是这里比的是「时间」而不是「像素」，而且多加一条**绝对下限**：
/// 课间 5 分钟、大课间 10 分钟这种，比值再大也只是课间，不是午休。
///
/// ## 为什么不能只看"最大间隔"
///
/// 一张课间均匀的课表，最大间隔也只是普通课间。随手切一刀会把下午的课
/// 误判成上午的（同一类错误在解析器里踩过一次，见 `period_time.dart`）。
int? lunchBreakAfterPeriod(
  List<PeriodTime> periods, {
  double gapRatio = 2.5,
  int minGapMinutes = 30,
}) {
  // 一两节谈不上"分段"
  if (periods.length < 3) return null;

  final List<int> gaps = <int>[];
  for (int i = 1; i < periods.length; i++) {
    gaps.add(periods[i].startMinute - periods[i - 1].endMinute);
  }

  int bestIndex = 0;
  for (int i = 1; i < gaps.length; i++) {
    if (gaps[i] > gaps[bestIndex]) bestIndex = i;
  }
  final int best = gaps[bestIndex];

  if (best < minGapMinutes) return null;

  final List<int> sorted = List<int>.of(gaps)..sort();
  final int median = sorted[sorted.length ~/ 2];

  // median 为 0 时（节次首尾相接）跳过比值判断 —— 这种课表恰恰是
  // "只有午休一个大空档"，该认出来
  if (median > 0 && best < median * gapRatio) return null;

  return periods[bestIndex].period;
}
