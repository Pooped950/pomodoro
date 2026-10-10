import 'package:meta/meta.dart';

/// 课表里的一门课 —— 「星期 × 节次区间」上的一个格子。
///
/// ## 为什么节次是**区间**而不是单个数
///
/// 真实课表里一门课常常连排两节（图上是一个跨两行的格子）。解析器已经能反推出
/// 这个区间（见 `timetable_grid.dart` 的 `ParsedCell.startPeriod/endPeriod`），
/// 所以这里保留区间 —— 周视图要靠它做**行合并**，把两行画成一格。
@immutable
class Course {
  const Course({
    required this.id,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.name,
    this.location = '',
    this.colorIndex = 0,
    required this.createdAt,
  });

  final int id;

  /// 1 = 周一 … 7 = 周日
  final int weekday;

  /// 起节次（从 1 开始）
  final int startPeriod;

  /// 止节次（含）
  final int endPeriod;

  final String name;
  final String location;

  /// 配色序号 —— **导入时算好存下来**，不每次现算。
  /// 现算的话，哪天调色板一改，历史课表的颜色会全部重排，看着像换了个 App。
  final int colorIndex;

  final DateTime createdAt;

  /// 占了几个节次
  int get periodSpan => endPeriod - startPeriod + 1;

  /// 是否跨节（连排两节及以上）
  bool get spansMultiplePeriods => periodSpan > 1;

  Course copyWith({
    int? weekday,
    int? startPeriod,
    int? endPeriod,
    String? name,
    String? location,
    int? colorIndex,
  }) =>
      Course(
        id: id,
        weekday: weekday ?? this.weekday,
        startPeriod: startPeriod ?? this.startPeriod,
        endPeriod: endPeriod ?? this.endPeriod,
        name: name ?? this.name,
        location: location ?? this.location,
        colorIndex: colorIndex ?? this.colorIndex,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Course &&
          other.id == id &&
          other.weekday == weekday &&
          other.startPeriod == startPeriod &&
          other.endPeriod == endPeriod &&
          other.name == name &&
          other.location == location &&
          other.colorIndex == colorIndex &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        weekday,
        startPeriod,
        endPeriod,
        name,
        location,
        colorIndex,
        createdAt,
      );

  @override
  String toString() => 'Course(#$id 周$weekday 第$startPeriod-$endPeriod节 '
      '"$name"${location.isEmpty ? '' : ' @$location'})';
}

/// 行映射 —— 表结构见 `AppDatabase._createV3Tables`。
class CourseMapper {
  const CourseMapper._();

  static Map<String, Object?> toRow(Course c) => <String, Object?>{
        'id': c.id,
        'weekday': c.weekday,
        'start_period': c.startPeriod,
        'end_period': c.endPeriod,
        'name': c.name,
        'location': c.location,
        'color_index': c.colorIndex,
        'created_at': c.createdAt.toIso8601String(),
      };

  /// 新增时用：不含 id，交给 SQLite 自增
  static Map<String, Object?> toInsertRow(Course c) {
    final Map<String, Object?> row = toRow(c)..remove('id');
    return row;
  }

  static Course fromRow(Map<String, Object?> row) => Course(
        id: (row['id'] as int?) ?? 0,
        weekday: (row['weekday'] as int?) ?? 1,
        startPeriod: (row['start_period'] as int?) ?? 1,
        endPeriod: (row['end_period'] as int?) ?? 1,
        name: (row['name'] as String?) ?? '',
        location: (row['location'] as String?) ?? '',
        colorIndex: (row['color_index'] as int?) ?? 0,
        createdAt:
            DateTime.tryParse((row['created_at'] as String?) ?? '') ??
                DateTime.now(),
      );
}

/// 给一批课程名分配配色序号。
///
/// 规则（用户 2026-10-06 明确要的）：**同一个课名永远同一个色**。
/// 所以是"按课名分配"而不是"按格子分配" —— 周一的高数和周五的高数必须同色，
/// 否则一眼看不出"这两格是同一门课"。
///
/// 新名字挑**当前用得最少**的那个色（并列时挑序号小的），这样色板摊得开，
/// 不会因为前两门课就反复撞一个色。
///
/// 纯函数，宿主机可直接单测。
Map<String, int> assignColorIndexes(Iterable<String> names, int paletteSize) {
  // release 下 assert 不生效，这里显式兜一下：调色板为空就当"没有配色"
  if (paletteSize <= 0) return <String, int>{};
  assert(paletteSize > 0, '调色板不能是空的');

  final Map<String, int> assigned = <String, int>{};
  final List<int> usage = List<int>.filled(paletteSize, 0);

  for (final String raw in names) {
    final String name = raw.trim();
    if (name.isEmpty) continue;
    if (assigned.containsKey(name)) continue;

    int best = 0;
    for (int i = 1; i < paletteSize; i++) {
      if (usage[i] < usage[best]) best = i;
    }
    assigned[name] = best;
    usage[best]++;
  }

  return assigned;
}

/// 教室名的**显示形态**：去掉导入时留下的装饰前缀。
///
/// 识别出来的教室是 `@腾龙楼408教室` 这种形态 —— 开头的 `@` 是课表 App
/// 用来分隔课名/教室的记号（识别阶段要靠它切分，见 `timetable_grid.dart`
/// 的 `_splitCellLines`）。
///
/// 但**画在格子里**的时候它纯属占地方：窄格子本来就放不下几个字，
/// 去掉它常常就是"教室能不能看全"的差别（2026-10-10 用户报
/// 「识别出来以后课表里教室显示不全」）。
///
/// 只剥**行首连续的** `@`，中间的不动（有些教室名真的带 @）。
String courseLocationForDisplay(String raw) {
  String s = raw.trim();
  while (s.startsWith('@')) {
    s = s.substring(1).trim();
  }
  return s;
}
