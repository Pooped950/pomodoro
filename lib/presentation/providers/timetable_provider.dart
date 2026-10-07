import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../data/repositories/timetable_repository.dart';
import '../../domain/timetable/course.dart';
import '../../domain/timetable/course_override.dart';
import '../../domain/timetable/period_time.dart';

/// 课表页要显示的全部数据：课程 + 时间轴
@immutable
class TimetableSnapshot {
  const TimetableSnapshot({
    required this.courses,
    required this.schedule,
    this.overrides = const <CourseOverride>[],
  });

  final List<Course> courses;
  final TimetableSchedule schedule;

  /// 单格例外（临时隐藏 / 临时加课）—— 「本周实际显示什么」由
  /// `effectiveCoursesForWeek` 按当前周计算，快照只带原始数据
  final List<CourseOverride> overrides;

  /// 完全没导入过 —— 课表页显示空白态
  bool get isEmpty => courses.isEmpty && schedule.periods.isEmpty;

  /// 一周里有课的那几天（1=周一 … 7=周日），升序
  List<int> get activeWeekdays {
    final Set<int> days = <int>{
      for (final Course c in courses) c.weekday,
    };
    final List<int> sorted = days.toList()..sort();
    return sorted;
  }
}

/// 课表数据源。
///
/// 导入完成后调 `ref.invalidate(timetableProvider)` 就能刷新 ——
/// 和统计页用 `statsProvider` 是同一个套路。
final timetableProvider = FutureProvider<TimetableSnapshot>(
  (Ref ref) async {
    final TimetableRepository repo = ref.watch(timetableRepositoryProvider);
    return TimetableSnapshot(
      courses: await repo.listCourses(),
      schedule: await repo.loadSchedule(),
      overrides: await repo.listOverrides(),
    );
  },
);
