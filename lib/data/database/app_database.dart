import 'package:sqflite/sqflite.dart';

/// 应用数据库单例 —— 方案文档 6.4「数据模型」。
///
/// - v1（M3 阶段一）：只建 `timer_snapshot`（计时快照，进程被杀后恢复用）
/// - v2（M4）：补 `tasks` / `sessions` / `settings` 三张表
///
/// 统计**不建表**，从 `sessions` 实时聚合（方案 6.4 的既定决策）。
///
/// 迁移注意：v1 → v2 只**新增**表，不动 `timer_snapshot`，
/// 所以老用户的计时快照不会丢。建表语句一律带 `IF NOT EXISTS`，
/// 让 onCreate 与 onUpgrade 两条路径共用同一段代码、可重复执行。
class AppDatabase {
  AppDatabase._();

  static Database? _db;

  static const String _dbName = 'pomodoro.db';
  static const int _dbVersion = 2;

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
      },
      onUpgrade: (Database d, int from, int to) async {
        if (from < 2) await _createV2Tables(d);
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
}
