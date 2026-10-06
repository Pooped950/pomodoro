/// 时长格式化工具。
///
/// 单独抽出来是为了能写单元测试——格式化逻辑出错的概率比想象中高
/// （尤其是补零和跨小时的处理）。
library;

/// 把秒数格式化成 `mm:ss`。
///
/// 负数按 0 处理，超过 99 分钟时正常进位（如 125 分钟 -> `125:00`）。
String formatClock(int totalSeconds) {
  final int s = totalSeconds < 0 ? 0 : totalSeconds;
  final int minutes = s ~/ 60;
  final int seconds = s % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

/// 把秒数格式化成人类可读的时长，如 `2h 15m`、`45m`、`30s`。
///
/// 用于统计页展示，不用于计时显示。
String formatDurationHuman(int totalSeconds) {
  final int s = totalSeconds < 0 ? 0 : totalSeconds;
  if (s < 60) return '${s}s';

  final int hours = s ~/ 3600;
  final int minutes = (s % 3600) ~/ 60;

  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

/// 把分钟数转成中文可读描述，如 `25 分钟`。
String formatMinutes(int minutes) => '$minutes 分钟';
