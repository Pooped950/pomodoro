import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/timetable/course.dart';
import '../../domain/timetable/course_override.dart';
import '../../domain/timetable/period_time.dart';

/// 课表三张表的读写 —— 表结构见 `AppDatabase._createV3Tables`。
///
/// ## 为什么晚自习存进 `settings` 而不是单开一张表
///
/// 晚自习是"一整块时间"，没有节次、没有课，本质是**课表级的元信息**。
/// 为它单开一张只有两列的表不划算，而 `settings` 本来就是 key-value + JSON、
/// 专门为"以后加东西不用改表结构"设计的（见 `SettingsRepository` 的注释）。
///
/// 还有一个现实理由：v3 已经发出去了（用户手机上已经建好），**再往 v3 里加表
/// 不会触发 onUpgrade** —— 老库停在 v3 就永远拿不到新表。要么升 v4，要么用
/// settings。这里选后者。
class TimetableRepository {
  TimetableRepository(this._db);

  final Database _db;

  /// 课表级元信息（当前只有晚自习起止）的存储键
  static const String keyMeta = 'timetable_meta';

  /// 全部课程，按「星期 → 节次」排好
  Future<List<Course>> listCourses() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'courses',
      orderBy: 'weekday ASC, start_period ASC, id ASC',
    );
    return rows.map(CourseMapper.fromRow).toList();
  }

  Future<List<PeriodTime>> listPeriodTimes() async {
    final List<Map<String, Object?>> rows =
        await _db.query('period_times', orderBy: 'period ASC');
    return rows
        .map((Map<String, Object?> r) => PeriodTime(
              period: (r['period'] as int?) ?? 0,
              startMinute: (r['start_minute'] as int?) ?? 0,
              endMinute: (r['end_minute'] as int?) ?? 0,
            ))
        .toList();
  }

  /// 读整张时间轴（节次表 + 晚自习）
  Future<TimetableSchedule> loadSchedule() async => TimetableSchedule(
        periods: await listPeriodTimes(),
        evening: await readEvening(),
      );

  /// 晚自习起止。没存过 / 脏数据 → null（当作"没有晚自习"）
  Future<EveningBlock?> readEvening() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: <Object>[keyMeta],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final Object? raw = rows.first['value'];
    if (raw is! String) return null;

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Object? start = decoded['eveningStart'];
      final Object? end = decoded['eveningEnd'];
      if (start is! int || end is! int || end <= start) return null;
      return EveningBlock(startMinute: start, endMinute: end);
    } catch (_) {
      // 脏数据不该让课表页起不来，当作没存过
      return null;
    }
  }

  /// **导入**：整表替换。
  ///
  /// 放在一个事务里 —— 中途失败不能留下"课程写了一半、时间表还是旧的"的
  /// 半成品课表，那比导入失败更糟（用户会以为导入成功了）。
  Future<void> replaceAll({
    required List<Course> courses,
    required TimetableSchedule schedule,
  }) async {
    await _db.transaction((Transaction txn) async {
      await txn.delete('courses');
      for (final Course c in courses) {
        await txn.insert('courses', CourseMapper.toInsertRow(c));
      }

      await txn.delete('period_times');
      for (final PeriodTime p in schedule.periods) {
        await txn.insert(
          'period_times',
          <String, Object?>{
            'period': p.period,
            'start_minute': p.startMinute,
            'end_minute': p.endMinute,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await txn.insert(
        'settings',
        <String, Object?>{
          'key': keyMeta,
          'value': jsonEncode(<String, Object?>{
            'eveningStart': schedule.evening?.startMinute,
            'eveningEnd': schedule.evening?.endMinute,
          }),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// 清空课表（换学期 / 重新导入前用）
  Future<void> clear() async {
    await _db.transaction((Transaction txn) async {
      await txn.delete('courses');
      await txn.delete('period_times');
      await txn.delete(
        'settings',
        where: 'key = ?',
        whereArgs: <Object>[keyMeta],
      );
    });
  }

  /// 改某一节的时间 —— 全局节次时间表（用户说的"两个都要"里的全局那一层）
  Future<void> updatePeriodTime(PeriodTime p) async {
    await _db.insert(
      'period_times',
      <String, Object?>{
        'period': p.period,
        'start_minute': p.startMinute,
        'end_minute': p.endMinute,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ------------------------------------------------------------------
  // 单格例外（course_overrides）—— 三点点菜单的读写层
  // ------------------------------------------------------------------

  /// 全部例外。**按周过滤交给领域层**（[effectiveCoursesForWeek]）——
  /// "哪一周生效"是纯计算，放 SQL 里反而难测。
  Future<List<CourseOverride>> listOverrides() async {
    final List<Map<String, Object?>> rows =
        await _db.query('course_overrides', orderBy: 'id ASC');
    return rows.map(CourseOverrideMapper.fromRow).toList();
  }

  /// 新增一条例外，返回自增 id（"恢复显示"要按 id 删）
  Future<int> insertOverride(CourseOverride o) =>
      _db.insert('course_overrides', CourseOverrideMapper.toInsertRow(o));

  /// 删除一条例外（临时隐藏的"恢复"就是删掉那条 hide）
  Future<void> deleteOverride(int id) => _db.delete(
        'course_overrides',
        where: 'id = ?',
        whereArgs: <Object>[id],
      );

  /// 永久删除一门课 —— 直接删骨架行，不走 override
  /// （override 是给"会自动失效的例外"用的，见 `course_override.dart`）
  Future<void> deleteCourse(int id) => _db.delete(
        'courses',
        where: 'id = ?',
        whereArgs: <Object>[id],
      );

  /// 永久加一门课，返回自增 id
  Future<int> insertCourse(Course c) =>
      _db.insert('courses', CourseMapper.toInsertRow(c));
}

/// 依赖注入：main() 里数据库就绪后用 overrideWithValue 注入真实实例。
final timetableRepositoryProvider = Provider<TimetableRepository>(
  (Ref ref) => throw UnimplementedError(
    'timetableRepositoryProvider 必须在 main() 里 override',
  ),
);
