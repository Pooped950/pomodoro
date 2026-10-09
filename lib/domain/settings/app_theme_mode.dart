/// 主题模式（外观设置）—— M4 设置页补齐。
///
/// 独立于 `TimerConfig`：计时配置属于「番茄怎么跑」，主题属于「界面长什么样」，
/// 分开存 key，以后各自演进互不影响。
enum AppThemeMode {
  /// 跟随系统
  system('跟随系统'),

  /// 强制浅色
  light('浅色'),

  /// 强制深色（**默认** —— 2026-10-09 用户要求，番茄红在深底上更出彩）
  dark('深色');

  const AppThemeMode(this.label);

  /// 设置页显示用的中文名
  final String label;

  /// 从持久化字符串还原；不认识（脏数据 / 老版本）回退到 [dark]
  /// （= 默认值）。不用 `firstWhere` 的 `orElse` 抛异常，
  /// 界面不该因为一个脏值崩掉。
  static AppThemeMode fromName(String? name) {
    for (final AppThemeMode m in AppThemeMode.values) {
      if (m.name == name) return m;
    }
    return AppThemeMode.dark;
  }
}
