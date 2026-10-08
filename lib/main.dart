import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/database/app_database.dart';
import 'data/repositories/session_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/task_repository.dart';
import 'data/repositories/timer_snapshot_repository.dart';
import 'data/repositories/timetable_repository.dart';
import 'data/services/remote_config_service.dart';
import 'data/services/update_service.dart';
import 'presentation/providers/remote_config_provider.dart';
import 'presentation/providers/update_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 数据库就绪后再进 UI：快照落盘与恢复从第一帧起就可用（M3）
  final database = await AppDatabase.instance();
  final settings = SettingsRepository(database);

  // ProviderScope 是 Riverpod 的根容器，必须包在最外层
  runApp(ProviderScope(
    overrides: [
      timerSnapshotRepositoryProvider
          .overrideWithValue(TimerSnapshotRepository(database)),
      // M4：sessions 记录与"今日 N/8"聚合
      sessionRepositoryProvider.overrideWithValue(SessionRepository(database)),
      // M4：设置持久化（TimerConfig 等）
      settingsRepositoryProvider.overrideWithValue(settings),
      // M5：任务（把番茄绑定到具体任务）
      taskRepositoryProvider.overrideWithValue(TaskRepository(database)),
      // 课表（v3）：课程 / 节次时间表 / 晚自习
      timetableRepositoryProvider
          .overrideWithValue(TimetableRepository(database)),
      // 检查更新：读远端 version.json + 缓存（复用同一份设置表）
      updateServiceProvider.overrideWithValue(
        UpdateService(store: SettingsUpdateStore(settings)),
      ),
      // 远程配置：课表识别规则 / 品牌配色 / 界面文案 —— 免安装生效
      remoteConfigServiceProvider.overrideWithValue(
        RemoteConfigService(store: SettingsUpdateStore(settings)),
      ),
    ],
    child: const PomodoroApp(),
  ));
}
