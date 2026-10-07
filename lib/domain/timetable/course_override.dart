import 'package:meta/meta.dart';

import 'course.dart';

/// 对标准课表的一处**例外**。
///
/// ## 为什么要单独一张表（表结构见 `AppDatabase._createV3Tables`）
///
/// 标准课表（`courses`）是"每周都一样"的骨架；现实里总有例外：
/// 这周调课、这节暂时不上、临时加一节。把这些例外记成一条条 override，
/// **骨架不动**：
///   - `weekMonday` 有值 = 只在那一周生效，过了自动失效 ——
///     这就是「临时删除，下周自动回来」的实现方式，不用填开学日期
///   - `weekMonday` 为空 = 永久生效（当前只有改时间会用到，见 retime）
///
/// ## 三种 kind
///
///   - [CourseOverrideKind.hide] 临时隐藏一格（本周不显示）
///   - [CourseOverrideKind.add] 临时加一节（本周多出来）
///   - [CourseOverrideKind.retime] 单格改时间 —— 本轮（三点点菜单）不做 UI，
///     读写层先支持，字段就位（startMinute/endMinute）
///
/// **永久**的例外不进这张表：永久删除 = 直接删 `courses` 的行；
/// 永久加课 = 直接插一行。表里只放"会自动失效的"。
@immutable
class CourseOverride {
  const CourseOverride({
    required this.id,
    required this.kind,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    this.weekMonday,
    this.name = '',
    this.location = '',
    this.startMinute,
    this.endMinute,
    required this.createdAt,
  });

  final int id;
  final CourseOverrideKind kind;

  /// 1 = 周一 … 7 = 周日
  final int weekday;
  final int startPeriod;
  final int endPeriod;

  /// 生效周的周一（0 点）；null = 不限周
  final DateTime? weekMonday;

  final String name;
  final String location;

  /// retime 专用：该格改成的起止时刻（距 0 点分钟数）
  final int? startMinute;
  final int? endMinute;

  final DateTime createdAt;

  /// 格子的定位键 —— 隐藏/恢复按「星期 + 起止节次」匹配一个格子
  String get cellKey => cellKeyOf(weekday, startPeriod, endPeriod);

  CourseOverride copyWith({int? id}) => CourseOverride(
        id: id ?? this.id,
        kind: kind,
        weekday: weekday,
        startPeriod: startPeriod,
        endPeriod: endPeriod,
        weekMonday: weekMonday,
        name: name,
        location: location,
        startMinute: startMinute,
        endMinute: endMinute,
        createdAt: createdAt,
      );

  @override
  String toString() => 'Override#$id ${kind.name} 周$weekday '
      '第$startPeriod-$endPeriod节${weekMonday == null ? '' : ' @${weekMonday!.toIso8601String().substring(0, 10)}'}';
}

enum CourseOverrideKind { hide, add, retime }

CourseOverrideKind kindOf(String raw) => CourseOverrideKind.values
    .firstWhere((CourseOverrideKind k) => k.name == raw,
        orElse: () => CourseOverrideKind.hide);

/// 格子定位键：`星期:起-止`
String cellKeyOf(int weekday, int startPeriod, int endPeriod) =>
    '$weekday:$startPeriod-$endPeriod';

/// 行映射 —— 表结构见 `AppDatabase._createV3Tables`
class CourseOverrideMapper {
  const CourseOverrideMapper._();

  static Map<String, Object?> toInsertRow(CourseOverride o) =>
      <String, Object?>{
        'kind': o.kind.name,
        'weekday': o.weekday,
        'start_period': o.startPeriod,
        'end_period': o.endPeriod,
        'week_monday': o.weekMonday?.toIso8601String().substring(0, 10),
        'name': o.name,
        'location': o.location,
        'start_minute': o.startMinute,
        'end_minute': o.endMinute,
        'created_at': o.createdAt.toIso8601String(),
      };

  static CourseOverride fromRow(Map<String, Object?> row) {
    final Object? monday = row['week_monday'];
    final Object? start = row['start_minute'];
    final Object? end = row['end_minute'];
    return CourseOverride(
      id: (row['id'] as int?) ?? 0,
      kind: kindOf((row['kind'] as String?) ?? 'hide'),
      weekday: (row['weekday'] as int?) ?? 1,
      startPeriod: (row['start_period'] as int?) ?? 1,
      endPeriod: (row['end_period'] as int?) ?? 1,
      weekMonday:
          monday is String ? DateTime.tryParse(monday) : null,
      name: (row['name'] as String?) ?? '',
      location: (row['location'] as String?) ?? '',
      startMinute: start is int ? start : null,
      endMinute: end is int ? end : null,
      createdAt:
          DateTime.tryParse((row['created_at'] as String?) ?? '') ??
              DateTime.now(),
    );
  }
}

/// [now] 所在周的周一（0 点）。周一就是今天。
DateTime mondayOf(DateTime now) {
  final DateTime day = DateTime(now.year, now.month, now.day);
  // Dart 的 weekday：周一=1 … 周日=7
  return day.subtract(Duration(days: now.weekday - 1));
}

/// 算出**这一周实际要显示**的课表：骨架课表 + 本周生效的例外。
///
/// 纯函数，宿主机可直接单测。规则：
///   - `hide`（本周生效）：从骨架里**剔除**对应格子
///   - `add`（本周生效）：合成一节临时课插进去 —— id 用**负的 override id**，
///     永远不会和 `courses` 的自增 id 撞（临时课落库前不需要真 id）
///   - `retime`：本轮菜单还没做改时间，先忽略（有数据也不崩）
///   - `weekMonday` 不等于本周的例外一律无效 —— "临时"到点自动消失
List<Course> effectiveCoursesForWeek({
  required List<Course> courses,
  required List<CourseOverride> overrides,
  required DateTime weekMonday,
}) {
  bool sameWeek(DateTime? monday) =>
      monday != null && _dayEq(monday, weekMonday);

  bool hidden(Course c) {
    for (final CourseOverride o in overrides) {
      if (o.kind != CourseOverrideKind.hide) continue;
      if (!sameWeek(o.weekMonday)) continue;
      if (o.cellKey ==
          cellKeyOf(c.weekday, c.startPeriod, c.endPeriod)) {
        return true;
      }
    }
    return false;
  }

  final List<Course> out = <Course>[
    for (final Course c in courses)
      if (!hidden(c)) c,
  ];
  for (final CourseOverride o in overrides) {
    if (o.kind != CourseOverrideKind.add) continue;
    if (!sameWeek(o.weekMonday)) continue;
    out.add(Course(
      id: -o.id,
      weekday: o.weekday,
      startPeriod: o.startPeriod,
      endPeriod: o.endPeriod,
      name: o.name.trim().isEmpty ? '临时课' : o.name.trim(),
      location: o.location,
      colorIndex: 0,
      createdAt: o.createdAt,
    ));
  }
  // 排序交给调用方（周视图自己有排序），这里保持骨架序 + 追加临时课
  return out;
}

bool _dayEq(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
