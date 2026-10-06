import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/database/app_database.dart';
import 'data/repositories/session_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/task_repository.dart';
import 'data/repositories/timer_snapshot_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 数据库就绪后再进 UI：快照落盘与恢复从第一帧起就可用（M3）
  final database = await AppDatabase.instance();

  // ProviderScope 是 Riverpod 的根容器，必须包在最外层
  runApp(ProviderScope(
    overrides: [
      timerSnapshotRepositoryProvider
          .overrideWithValue(TimerSnapshotRepository(database)),
      // M4：sessions 记录与"今日 N/8"聚合
      sessionRepositoryProvider.overrideWithValue(SessionRepository(database)),
      // M4：设置持久化（TimerConfig 等）
      settingsRepositoryProvider.overrideWithValue(SettingsRepository(database)),
      // M5：任务（把番茄绑定到具体任务）
      taskRepositoryProvider.overrideWithValue(TaskRepository(database)),
    ],
    child: const PomodoroApp(),
  ));
}
