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
///
/// ⚠️ 顺手也做一遍 [dedupeLocationPrefix]：老版本导入的数据里已经存了
/// 拼重复的教室名（`桃花坪三教桃花坪三教210教室`），显示时清一遍，
/// 用户不用重新导入就能看到干净的结果。
String courseLocationForDisplay(String raw) {
  String s = raw.trim();
  while (s.startsWith('@')) {
    s = s.substring(1).trim();
  }
  return dedupeLocationPrefix(s);
}

/// 去掉教室名里**识别阶段拼重复**的冗余前缀。
///
/// ## 为什么会有重复（2026-10-10 真机实测）
///
/// 这款课表 App 的教室名很长（`桃花坪四教(实训楼)304教室`），OCR 会把
/// 同一横排相邻两列的文字粘成一条**跨列行**，拆分时如果切点偏了，
/// 前半段的楼栋名就会和后半段的完整教室名**叠在一起**：
///
/// | 脏数据 | 应该是什么 |
/// |---|---|
/// | `桃花坪三教桃花坪三教210教室` | `桃花坪三教210教室` |
/// | `树达楼桃花坪树达楼307教室` | `树达楼307教室` |
/// | `桃花坪四教(实训楼)花坪四教(实训楼)304教室` | `桃花坪四教(实训楼)304教室` |
/// | `桃花坪一教(达善楼)桃花坪一教(达善楼)A02A04` | `桃花坪一教(达善楼)A02A04` |
///
/// 实测 11 门课里 **10 门**都这样 —— 不是偶发，是系统性拼接。
///
/// ## 判据（三种重复形态，都要求"后半段本身是完整的"）
///
///   1. **整段重复**：后半段以整个前半段开头
///   2. **尾部重叠**：前半段的**结尾**等于后半段的**开头**（少一两个字的重复）
///   3. **同头**：前半段和后半段**开头相同**（前半是"楼栋+校区"，后半才是房间）
///
/// ⚠️ 只认这三种**明确的**重复。真实教室名（`桃花坪四教(实训楼)304`）
/// 三种都匹配不上，原样返回 —— 宁可不改，也不能把好数据改坏。
String dedupeLocationPrefix(String raw) {
  final String s = raw.trim();
  if (s.length < 6) return s;

  for (int cut = 2; cut <= s.length - 2; cut++) {
    final String head = s.substring(0, cut);
    final String rest = s.substring(cut);
    if (rest.isEmpty) break;

    // ① 整段重复：`桃花坪三教` + `桃花坪三教210教室`
    if (rest.startsWith(head)) {
      final String fixed = dedupeLocationPrefix(rest);
      return fixed;
    }

    // ② 尾部重叠：`桃花坪四教(实训楼)` + `花坪四教(实训楼)304教室`
    //    head 的结尾 == rest 的开头（至少 2 字，免得单字巧合）
    final int maxK = head.length < rest.length ? head.length : rest.length;
    for (int k = maxK; k >= 2; k--) {
      if (head.endsWith(rest.substring(0, k))) {
        return s.substring(0, cut - k) + rest;
      }
    }

    // ③ 同头：`树达楼桃花坪` + `树达楼307教室`
    //    要求 head 几乎整个都是 rest 的前缀（差不超过 2 字），
    //    说明 head 只是"楼栋+校区"的冗余描述
    final int cp = _commonPrefixLen(head, rest);
    if (cp >= 2 && head.length - cp <= 2) {
      return rest;
    }

    // ④ 同头 + 后半段带房间号：`树达楼桃花坪` + `树达楼307教室`
    //    这类前半段是"楼栋 + 校区"，后半段才是"楼栋 + 房间"。
    //    要求后半段**含数字**（房间号），免得把两个并列地点误合并
    //    （`桃花坪四教(实训楼)桃花坪篮球场` 是真实的两段，不能动）。
    if (cp >= 2 && RegExp(r'\d').hasMatch(rest)) {
      return rest;
    }
  }
  return s;
}

/// 两个串的公共前缀长度
int _commonPrefixLen(String a, String b) {
  int i = 0;
  final int n = a.length < b.length ? a.length : b.length;
  while (i < n && a[i] == b[i]) {
    i++;
  }
  return i;
}
