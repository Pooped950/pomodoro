import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/class_reminder_service.dart';
import '../../domain/settings/class_reminder_settings.dart';
import '../../domain/timetable/class_reminder.dart';
import 'app_settings_provider.dart';
import 'timetable_provider.dart';

/// 上课提醒的通道封装
final classReminderServiceProvider = Provider<ClassReminderService>(
  (Ref ref) => const ClassReminderService(),
);

/// 当前生效的上课提醒条数（界面上给用户看一眼"已排 N 条"）
final classReminderCountProvider = FutureProvider<int>(
  (Ref ref) async =>
      ref.watch(classReminderServiceProvider).count(),
);

/// **课表一变就重排上课提醒。**
///
/// ## 为什么挂在 `timetableProvider` 上，而不是"导入成功回调"
///
/// 改课表的路不止一条：重新导入 / 编辑单格 / 删课 / 改节次时间 ——
/// 监听数据源才不会漏。导入完成后本来就会 `invalidate(timetableProvider)`，
/// 这里自然跟着跑。
///
/// ## 为什么是 `Provider<void>`
///
/// 它只负责"挂一个监听"这个副作用，没有值可返回。用它的方式是在根部
/// `ref.watch(classReminderSyncProvider)` —— 只要 App 活着就一直监听着。
final classReminderSyncProvider = Provider<void>((Ref ref) {
  void sync() {
    ref.read(timetableProvider).whenData((TimetableSnapshot s) {
      unawaited(syncClassReminders(ref, s));
    });
  }

  ref.listen<AsyncValue<TimetableSnapshot>>(
    timetableProvider,
    (AsyncValue<TimetableSnapshot>? _, AsyncValue<TimetableSnapshot> next) {
      next.whenData((TimetableSnapshot s) {
        unawaited(syncClassReminders(ref, s));
      });
    },
  );
  // 提醒方式一变立刻重排：两个都关掉时要**把已经排上的闹钟取消**，
  // 不能只是"下次不排"（那样已经排上的还会继续响）
  ref.listen<ClassReminderSettings>(
    classReminderSettingsProvider,
    (ClassReminderSettings? _, ClassReminderSettings _) => sync(),
  );
  // 首帧也要同步一次：App 启动时库里已经有课表，但监听只在"变化"时触发
  sync();
});

/// 算规则 → 交给原生排程。课表为空 / 提醒关掉就清掉所有提醒。
Future<void> syncClassReminders(Ref ref, TimetableSnapshot snapshot) async {
  final ClassReminderService svc = ref.read(classReminderServiceProvider);
  final ClassReminderSettings mode = ref.read(classReminderSettingsProvider);
  if (!mode.enabled ||
      snapshot.courses.isEmpty ||
      snapshot.schedule.periods.isEmpty) {
    await svc.clear();
    return;
  }
  final List<ClassReminder> reminders = buildClassReminders(
    courses: snapshot.courses,
    schedule: snapshot.schedule,
  );
  // 提醒方式（震动 / 响铃 / 两者）一并交给原生 —— 它按这个挑预建的通知渠道
  await svc.apply(reminders, mode: mode);
}
