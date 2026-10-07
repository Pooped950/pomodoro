import 'package:meta/meta.dart';

/// 一节课的起止时间 —— 存「距 0 点的分钟数」。
///
/// ## 为什么不用 DateTime / TimeOfDay
///
/// 课表时间是**墙上时间**（第 3 节就是 10:05），和日期、时区、夏令时全无关系。
/// 存分钟数最不容易出错，做加减也直接。
@immutable
class PeriodTime {
  const PeriodTime({
    required this.period,
    required this.startMinute,
    required this.endMinute,
  });

  /// 节次序号，从 1 开始
  final int period;

  /// 距 0 点的分钟数（8:00 → 480）
  final int startMinute;
  final int endMinute;

  int get durationMinutes => endMinute - startMinute;

  PeriodTime copyWith({int? startMinute, int? endMinute}) => PeriodTime(
        period: period,
        startMinute: startMinute ?? this.startMinute,
        endMinute: endMinute ?? this.endMinute,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PeriodTime &&
          other.period == period &&
          other.startMinute == startMinute &&
          other.endMinute == endMinute;

  @override
  int get hashCode => Object.hash(period, startMinute, endMinute);

  @override
  String toString() =>
      '第$period节 ${minutesToLabel(startMinute)}~${minutesToLabel(endMinute)}';
}

/// 晚自习 —— **一整块，不分节**。
///
/// 用户 2026-10-06 明确：晚自习不在课表图里（是课表外的内容），
/// 课表页只在最下面画一条时间条，不往里填课。
@immutable
class EveningBlock {
  const EveningBlock({required this.startMinute, required this.endMinute});

  final int startMinute;
  final int endMinute;

  int get durationMinutes => endMinute - startMinute;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EveningBlock &&
          other.startMinute == startMinute &&
          other.endMinute == endMinute;

  @override
  int get hashCode => Object.hash(startMinute, endMinute);

  @override
  String toString() =>
      '晚自习 ${minutesToLabel(startMinute)}~${minutesToLabel(endMinute)}';
}

/// 一整张节次时间表
@immutable
class TimetableSchedule {
  const TimetableSchedule({
    this.periods = const <PeriodTime>[],
    this.evening,
  });

  /// 按节次升序
  final List<PeriodTime> periods;

  final EveningBlock? evening;

  bool get isEmpty => periods.isEmpty && evening == null;

  /// 总节数（不含晚自习）
  int get periodCount => periods.length;

  PeriodTime? forPeriod(int period) {
    for (final PeriodTime p in periods) {
      if (p.period == period) return p;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimetableSchedule &&
          other.evening == evening &&
          other.periods.length == periods.length &&
          _samePeriods(other.periods, periods);

  static bool _samePeriods(List<PeriodTime> a, List<PeriodTime> b) {
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(periods), evening);
}

/// 用户填的那几个锚点（导入时问的"特定数据"）。
@immutable
class ScheduleAnchors {
  const ScheduleAnchors({
    required this.firstStartMinute,
    required this.morningEndMinute,
    required this.afternoonStartMinute,
    required this.lastEndMinute,
    required this.periodMinutes,
    required this.morningPeriodCount,
    required this.afternoonPeriodCount,
    this.eveningStartMinute,
    this.eveningEndMinute,
  });

  /// 最早一节课开始
  final int firstStartMinute;

  /// 上午最后一节结束
  final int morningEndMinute;

  /// 下午第一节开始
  final int afternoonStartMinute;

  /// 最晚一节课结束
  final int lastEndMinute;

  /// 每节课时长
  final int periodMinutes;

  /// 上午几节 / 下午几节 —— 由解析器从节次栏数出来（见 [morningPeriodCountFromAnchors]）
  final int morningPeriodCount;
  final int afternoonPeriodCount;

  final int? eveningStartMinute;
  final int? eveningEndMinute;

  bool get hasEvening => eveningStartMinute != null && eveningEndMinute != null;
}

/// 按锚点排出整张节次时间表。**纯函数，宿主机可直接单测。**
///
/// ## 每段内部按"均匀间隔"排
///
/// 已知这一段的起、止、节数和每节课时长，剩下的课间总时长平均分给 (节数-1) 个间隔。
///
/// ## ⚠️ 这只是"一次就对"的近似，不是最终答案
///
/// 真实课表里课间往往**不均**：上午第 2、3 节之间可能是 30 分钟大课间，其他间隔
/// 只有 5 分钟。光靠"每节时长"这一个数字推不出来。所以：
///   - 均匀排是**默认值**，让用户一次填完就有个八九不离十的表
///   - 用户可以在课表页**逐节改**（点左侧节次栏改全局时间），
///     也可以只改某一格（`course_overrides` 的 retime）
TimetableSchedule buildSchedule(ScheduleAnchors a) {
  final List<PeriodTime> periods = <PeriodTime>[
    ..._layoutBlock(
      firstPeriod: 1,
      count: a.morningPeriodCount,
      startMinute: a.firstStartMinute,
      endMinute: a.morningEndMinute,
      periodMinutes: a.periodMinutes,
    ),
    ..._layoutBlock(
      firstPeriod: a.morningPeriodCount + 1,
      count: a.afternoonPeriodCount,
      startMinute: a.afternoonStartMinute,
      endMinute: a.lastEndMinute,
      periodMinutes: a.periodMinutes,
    ),
  ];

  return TimetableSchedule(
    periods: periods,
    evening: a.hasEvening
        ? EveningBlock(
            startMinute: a.eveningStartMinute!,
            endMinute: a.eveningEndMinute!,
          )
        : null,
  );
}

/// 排一段（上午 / 下午）。见 [buildSchedule] 的说明。
List<PeriodTime> _layoutBlock({
  required int firstPeriod,
  required int count,
  required int startMinute,
  required int endMinute,
  required int periodMinutes,
}) {
  if (count <= 0) return const <PeriodTime>[];

  if (count == 1) {
    return <PeriodTime>[
      PeriodTime(
        period: firstPeriod,
        startMinute: startMinute,
        endMinute: startMinute + periodMinutes,
      ),
    ];
  }

  final int totalGap = (endMinute - startMinute) - count * periodMinutes;
  final int gap = totalGap <= 0 ? 0 : totalGap ~/ (count - 1);

  return <PeriodTime>[
    for (int i = 0; i < count; i++)
      PeriodTime(
        period: firstPeriod + i,
        startMinute: startMinute + i * (periodMinutes + gap),
        // 最后一节的结束时刻**钉在锚点上** —— "上午最后一节几点结束"是用户
        // 最确定的一条信息，不能因为取整而漂掉。
        // ⚠️ 但锚点必须**装得下**这些课：节数多了总时长超了锚点时，
        // 钉锚点会排出"11:45~11:40"这种倒挂（2026-10-07 真机实测踩到，
        // 用户填的默认时间和识别出的节数对不上）。宁可越过锚点，也不倒挂。
        endMinute: i == count - 1
            ? (endMinute > startMinute + i * (periodMinutes + gap)
                ? endMinute
                : startMinute + i * (periodMinutes + gap) + periodMinutes)
            : startMinute + i * (periodMinutes + gap) + periodMinutes,
      ),
  ];
}

/// 从节次栏的 y 锚点里找出**最大的那个间隔** —— 那就是午休，
/// 用它把节次切成"上午 / 下午"两段。
///
/// 返回上午的节数。纯函数。
///
/// 为什么要"明显大于"才认：一张间隔均匀的课表，最大间隔也是普通间隔，
/// 随手切一刀会把下午的课误判成上午的。所以要求最大间隔 ≥ 中位间隔的
/// [gapRatio] 倍（默认 1.8，和解析器聚格用的阈值同一个量级）。
int morningPeriodCountFromAnchors(
  List<double> anchorCentersY, {
  double gapRatio = 1.8,
}) {
  final int n = anchorCentersY.length;
  if (n < 3) return n; // 一两节谈不上"分段"

  double bestGap = -1;
  int splitAt = n;
  for (int i = 1; i < n; i++) {
    final double gap = anchorCentersY[i] - anchorCentersY[i - 1];
    if (gap > bestGap) {
      bestGap = gap;
      splitAt = i;
    }
  }

  final double median = _medianGap(anchorCentersY);
  if (median <= 0 || bestGap < median * gapRatio) return n;
  return splitAt;
}

double _medianGap(List<double> ys) {
  final List<double> gaps = <double>[];
  for (int i = 1; i < ys.length; i++) {
    gaps.add(ys[i] - ys[i - 1]);
  }
  if (gaps.isEmpty) return 0;
  gaps.sort();
  return gaps[gaps.length ~/ 2];
}

/// 从粘贴的**官方作息表文本**里解析出每节课的起止时间。
///
/// ## 为什么有这个入口（2026-10-07）
///
/// 锚点 + 均匀间隔排出来的时间是**近似**：真实学校的课间是不均匀的
/// （实测 10 / 15 / 10 / 65(午休) / 0 / 15 / 10 / 20 / 10 …分钟，第 5~6 节
/// 之间甚至是 0）。学生手里往往有官方作息表（教务系统 / 班级群 / Excel），
/// 直接粘进来按**精确时间**落库，锚点估算只留给没表的人兜底。
///
/// ## 容得多宽
///
/// 从 Excel 复制一格一行是 `08:00 ~ 08:45`（制表符分隔、全在一行）；
/// 手抄可能是 `1 08:00-08:45` 每行一条。所以不做行解析，直接
/// **全文找出所有"起~止"时间对**，按出现顺序就是第 1、2、3…节。
/// 认不出至少两对、或时间不合法（结束不晚于开始）时返回 null。
List<PeriodTime>? parsePeriodTable(String raw) {
  final RegExp pair = RegExp(
    r'(\d{1,2})[：:](\d{1,2})\s*[~～\-–—一出到]\s*(\d{1,2})[：:](\d{1,2})',
  );
  final List<PeriodTime> periods = <PeriodTime>[];
  for (final RegExpMatch m in pair.allMatches(raw)) {
    // 分钟数补零要补在自身上（'8:5' → '8:05'）；整体 padLeft 会垫错位置
    final int? start = labelToMinutes(
      '${m.group(1)}:${m.group(2)!.padLeft(2, '0')}',
    );
    final int? end = labelToMinutes(
      '${m.group(3)}:${m.group(4)!.padLeft(2, '0')}',
    );
    if (start == null || end == null || end <= start) return null;
    periods.add(PeriodTime(
      period: periods.length + 1,
      startMinute: start,
      endMinute: end,
    ));
  }
  // 少于两对不像一张作息表；多于二十对说明粘进来的多半不是作息表
  if (periods.length < 2 || periods.length > 20) return null;
  // 节次时间必须单调不减（官方表不会倒着排；乱序说明粘错了内容）
  for (int i = 1; i < periods.length; i++) {
    if (periods[i].startMinute < periods[i - 1].startMinute) return null;
  }
  return periods;
}

/// 480 → '08:00'。超过 24 小时按取模处理，不抛异常。
String minutesToLabel(int minutes) {
  final int m = ((minutes % 1440) + 1440) % 1440;
  final String hh = (m ~/ 60).toString().padLeft(2, '0');
  final String mm = (m % 60).toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// '08:00' / '8:00' / '0800' → 480；认不出来返回 null。
///
/// 宽容一点是有必要的：这是用户手输的，可能带空格、可能不补零。
int? labelToMinutes(String raw) {
  final String s = raw.trim().replaceAll('：', ':').replaceAll(' ', '');
  if (s.isEmpty) return null;

  final RegExpMatch? hm = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(s);
  if (hm != null) {
    final int h = int.parse(hm.group(1)!);
    final int m = int.parse(hm.group(2)!);
    if (h > 23 || m > 59) return null;
    return h * 60 + m;
  }

  final RegExpMatch? hhmm = RegExp(r'^(\d{2})(\d{2})$').firstMatch(s);
  if (hhmm != null) {
    final int h = int.parse(hhmm.group(1)!);
    final int m = int.parse(hhmm.group(2)!);
    if (h > 23 || m > 59) return null;
    return h * 60 + m;
  }

  return null;
}
