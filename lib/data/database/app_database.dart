import 'package:sqflite/sqflite.dart';

/// 应用数据库单例 —— 方案文档 6.4「数据模型」。
///
/// - v1（M3 阶段一）：只建 `timer_snapshot`（计时快照，进程被杀后恢复用）
/// - v2（M4）：补 `tasks` / `sessions` / `settings` 三张表
/// - v3（课表）：补 `courses` / `period_times` / `course_overrides` 三张表
///
/// 统计**不建表**，从 `sessions` 实时聚合（方案 6.4 的既定决策）。
///
/// 迁移注意：每一版都只**新增**表，不动老表，所以老用户的数据不会丢。
/// 建表语句一律带 `IF NOT EXISTS`，让 onCreate 与 onUpgrade 两条路径
/// 共用同一段代码、可重复执行。
///
/// ⚠️ 2026-10-06 更正：曾误记「v2 建表时 courses 表已存在」——**是错的**，
/// 课表三张表是 v3 才加的（见 `_createV3Tables`）。
class AppDatabase {
  AppDatabase._();

  static Database? _db;

  static const String _dbName = 'pomodoro.db';
  static const int _dbVersion = 3;

  static Future<Database> instance() async {
    final Database? existing = _db;
    if (existing != null) return existing;

    final String dir = await getDatabasesPath();
    final Database db = await openDatabase(
      '$dir/$_dbName',
      version: _dbVersion,
      onCreate: (Database d, int version) async {
        await _createV1Tables(d);
        await _createV2Tables(d);
        await _createV3Tables(d);
      },
      onUpgrade: (Database d, int from, int to) async {
        if (from < 2) await _createV2Tables(d);
        if (from < 3) await _createV3Tables(d);
      },
    );

    _db = db;
    return db;
  }

  /// 仅测试用：关掉单例，让下一次 instance() 重新打开
  static Future<void> closeForTest() async {
    await _db?.close();
    _db = null;
  }

  // ------------------------------------------------------------------

  /// v1：计时快照（单行表，id 恒为 1）
  static Future<void> _createV1Tables(Database d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS timer_snapshot (
        id INTEGER PRIMARY KEY,
        phase TEXT NOT NULL,
        started_at TEXT,
        planned_seconds INTEGER NOT NULL,
        paused_at TEXT,
        paused_total_seconds INTEGER NOT NULL DEFAULT 0,
        task_id INTEGER,
        round_index INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// v2：任务 / 记录 / 设置
  static Future<void> _createV2Tables(Database d) async {
    // 表 1：tasks
    await d.execute('''
      CREATE TABLE IF NOT EXISTS tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        estimated_pomodoros INTEGER NOT NULL DEFAULT 1,
        completed_pomodoros INTEGER NOT NULL DEFAULT 0,
        is_done INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        completed_at TEXT
      )
    ''');

    // 表 2：sessions —— 统计的唯一数据源
    await d.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER,
        phase TEXT NOT NULL,
        planned_seconds INTEGER NOT NULL,
        actual_seconds INTEGER NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        is_completed INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 统计几乎全是"按时间段查 sessions"，没有索引会随记录增长越来越慢
    await d.execute(
      'CREATE INDEX IF NOT EXISTS idx_sessions_started_at '
      'ON sessions (started_at)',
    );

    // 幂等保护：一次计时由 (phase, started_at) 唯一确定。
    // Dart 侧 _onTick 与原生前台服务可能**同时**推进阶段，
    // 两边都会尝试补写记录 —— 唯一索引 + INSERT OR IGNORE 让重复写入自动丢弃。
    await d.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_phase_started '
      'ON sessions (phase, started_at)',
    );

    // 表 3：settings —— key-value，value 用 JSON 序列化
    await d.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  /// v3：课表（2026-10-06）
  ///
  /// 三张表分工：
  ///   - `courses`：**课表内容本身** —— 一条 = 一周里某个「星期 + 节次区间」的一门课
  ///   - `period_times`：**节次时间表** —— 「第 3 节 10:05~10:50」这种全局时间。
  ///     和 `courses` 分开放是有意的：用户改一次「第 3 节几点」，全周的第 3 节一起变
  ///     （一周固定课表里，周一第 3 节和周五第 3 节本来就是同一时间）。
  ///     单格例外走 `course_overrides` 的 `retime`
  ///   - `course_overrides`：**单格例外** —— 临时删除 / 临时加课 / 单格改时间。
  ///     带 `week_monday`（本周周一的日期）：为空 = 永久；有值 = 只在那一周生效，
  ///     过了那一周自动失效 —— 这就是"临时删除，下周自动回来"的实现方式，
  ///     **不需要知道学期第几周**，只要知道"本周周一是哪天"
  ///
  /// 时间一律存「距 0 点的分钟数」而不是时间戳：课表时间是**墙上时间**
  /// （第 3 节就是 10:05），和日期/时区无关，存分钟数最不容易出错。
  static Future<void> _createV3Tables(Database d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS courses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        weekday INTEGER NOT NULL,
        start_period INTEGER NOT NULL,
        end_period INTEGER NOT NULL,
        name TEXT NOT NULL,
        location TEXT NOT NULL DEFAULT '',
        color_index INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // 周视图每次都要按「星期 + 节次」取，没索引会随课表变大越来越慢
    await d.execute(
      'CREATE INDEX IF NOT EXISTS idx_courses_slot '
      'ON courses (weekday, start_period)',
    );

    await d.execute('''
      CREATE TABLE IF NOT EXISTS period_times (
        period INTEGER PRIMARY KEY,
        start_minute INTEGER NOT NULL,
        end_minute INTEGER NOT NULL
      )
    ''');

    await d.execute('''
      CREATE TABLE IF NOT EXISTS course_overrides (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        weekday INTEGER NOT NULL,
        start_period INTEGER NOT NULL,
        end_period INTEGER NOT NULL,
        week_monday TEXT,
        name TEXT NOT NULL DEFAULT '',
        location TEXT NOT NULL DEFAULT '',
        start_minute INTEGER,
        end_minute INTEGER,
        created_at TEXT NOT NULL
      )
    ''');

    await d.execute(
      'CREATE INDEX IF NOT EXISTS idx_overrides_week '
      'ON course_overrides (week_monday, weekday, start_period)',
    );
  }
}
