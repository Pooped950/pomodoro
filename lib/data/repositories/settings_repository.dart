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

  /// **用户已经看过的使用手册版本**。
  ///
  /// 启动时拿它和 `kManualVersion` 比：不一样就弹一次手册。
  /// 所以首次安装会弹、发了新版本也会弹（顺便让老用户看到更新内容）。
  static const String keyManualSeenVersion = 'manual_seen_version';

  /// 上次弹过「大版本更新」弹窗时的 App 版本。
  /// 启动时和 `kAppVersion` 比 **major 段**：见过的小于当前的大版本就弹
  /// （小版本/补丁不弹，见 `update_dialog.dart` 的 `shouldShowMajorUpdateDialog`）。
  static const String keyUpdateSeenVersion = 'update_seen_version';

  /// 检查更新：上次**发起检查**的时间（ISO8601）。成功失败都记 ——
  /// 离线时也要节流，不然用户每进一次「我的」页就打一次网络。
  static const String keyUpdateLastCheckAt = 'update_last_check_at';

  /// 检查更新：上次**成功**拉到的版本文件原文。
  /// 存原文而不是解析结果，是为了解析逻辑升级后缓存还能用；离线时也能显示
  /// "上次看到的最新版本 + 更新说明"。
  static const String keyUpdateCachedJson = 'update_cached_json';

  /// 检查更新：已经弹过「更新说明」的那个 versionCode（`prompt` 档只弹一次）。
  static const String keyUpdatePromptedVersionCode = 'update_prompted_version_code';

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
