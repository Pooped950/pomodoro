import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/timer/timer_engine.dart';

/// `settings` 表的读写 —— 方案文档 6.4 表 3。
///
/// 设计成 key-value + JSON value：以后加设置项（主题模式、提醒开关…）
/// 只加一个 key，**不用改表结构、不用写迁移**。
class SettingsRepository {
  SettingsRepository(this._db);

  final Database _db;

  /// 计时配置（TimerConfig）的存储键
  static const String keyTimerConfig = 'timer_config';

  /// 主题模式（AppThemeMode）的存储键
  static const String keyThemeMode = 'theme_mode';

  /// 到点提醒（ReminderSettings）的存储键
  static const String keyReminder = 'reminder';

  /// 计时页当前选中的任务 id（M5）。空字符串 = 未选。
  static const String keySelectedTaskId = 'selected_task_id';

  /// 动效节奏倍率（全局动画时长倍率）。默认「从容」档。
  static const String keyMotionScale = 'motion_scale';

  /// 主页背景（预设色卡 / 相册照片）。
  static const String keyBackground = 'background';

  /// 读一个字符串值；没存过 / 类型不对返回 null
  Future<String?> readString(String key) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: <Object>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final Object? raw = rows.first['value'];
    if (raw is! String) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is String ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeString(String key, String value) async {
    await _db.insert(
      'settings',
      <String, Object?>{'key': key, 'value': jsonEncode(value)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, Object?>?> readJson(String key) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: <Object>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final Object? raw = rows.first['value'];
    if (raw is! String) return null;

    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } catch (_) {
      // 脏数据（手工改过库 / 旧版本格式）不该让 App 起不来，当作没存过
      return null;
    }
  }

  Future<void> writeJson(String key, Map<String, Object?> value) async {
    await _db.insert(
      'settings',
      <String, Object?>{'key': key, 'value': jsonEncode(value)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 读计时配置；从未存过返回 null（调用方回退到默认值）
  Future<TimerConfig?> readTimerConfig() async {
    final Map<String, Object?>? json = await readJson(keyTimerConfig);
    return json == null ? null : TimerConfig.fromJson(json);
  }

  Future<void> writeTimerConfig(TimerConfig config) =>
      writeJson(keyTimerConfig, config.toJson());
}

/// 依赖注入：main() 里数据库就绪后用 overrideWithValue 注入真实实例。
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (Ref ref) => throw UnimplementedError(
    'settingsRepositoryProvider 必须在 main() 里 override',
  ),
);
