import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// 四项后台保活开关的状态快照（M3 阶段四）。
///
/// 为什么需要它：澎湃OS / MIUI 的后台管理比原生激进 —— 光有前台服务和精确闹钟
/// 不够，用户还得手动开「自启动」、把「省电策略」设为无限制，否则息屏后进程会
/// 被系统杀掉，到点提醒自然不响。这些开关没有公开 API 可改，只能查状态 + 引导。
@immutable
class KeepAliveStatus {
  const KeepAliveStatus({
    required this.notificationsEnabled,
    required this.exactAlarmAllowed,
    required this.batteryUnrestricted,
    this.autoStartAllowed,
    this.isMiuiLike = false,
  });

  /// 拿不到原生状态时的安全默认：**当作"都还没开"**，
  /// 宁可让用户看到待办项，也不要谎报"已就绪"。
  factory KeepAliveStatus.unknown() => const KeepAliveStatus(
        notificationsEnabled: false,
        exactAlarmAllowed: false,
        batteryUnrestricted: false,
      );

  /// 通知权限（Android 13+ 是运行时权限；被关掉后所有通知都会被系统丢弃）
  final bool notificationsEnabled;

  /// 精确闹钟权限（`USE_EXACT_ALARM`，Android 13+ 系统自动授予，此处只作展示）
  final bool exactAlarmAllowed;

  /// 省电策略是否为「无限制」
  final bool batteryUnrestricted;

  /// 自启动：MIUI / HyperOS 的私有 AppOps，**查不到时为 null（未知）**，
  /// 不要当成 false —— 那会让用户以为自己没开。
  final bool? autoStartAllowed;

  /// 是否小米系 ROM
  final bool isMiuiLike;

  /// 明确"没开"的项数。自启动未知时不计入（避免误报）。
  int get pendingCount => <bool>[
        !notificationsEnabled,
        !exactAlarmAllowed,
        !batteryUnrestricted,
        autoStartAllowed == false,
      ].where((bool v) => v).length;

  /// 是否全部就绪（自启动未知时按就绪算，不阻塞"全绿"判断）
  bool get allReady => pendingCount == 0;

  static KeepAliveStatus fromMap(Map<Object?, Object?>? m) {
    if (m == null) return KeepAliveStatus.unknown();
    return KeepAliveStatus(
      notificationsEnabled: m['notificationsEnabled'] as bool? ?? false,
      exactAlarmAllowed: m['exactAlarmAllowed'] as bool? ?? false,
      batteryUnrestricted: m['batteryUnrestricted'] as bool? ?? false,
      autoStartAllowed: m['autoStartAllowed'] as bool?,
      isMiuiLike: m['isMiuiLike'] as bool? ?? false,
    );
  }

  @override
  String toString() => 'KeepAliveStatus(通知: $notificationsEnabled, '
      '精确闹钟: $exactAlarmAllowed, 省电无限制: $batteryUnrestricted, '
      '自启动: ${autoStartAllowed ?? '未知'}, MIUI系: $isMiuiLike)';
}

/// 后台保活通道封装 —— MethodChannel("pomodoro/keepalive")。
///
/// 与 `ForegroundService` 同样的风格：异常全部吞掉转为安全值，
/// 让"没有原生层"（测试环境）不影响页面渲染。
class KeepAliveService {
  static const MethodChannel _channel = MethodChannel('pomodoro/keepalive');

  Future<KeepAliveStatus> status() async {
    try {
      final Map<Object?, Object?>? m =
          await _channel.invokeMethod<Map<Object?, Object?>>('status');
      return KeepAliveStatus.fromMap(m);
    } catch (_) {
      return KeepAliveStatus.unknown();
    }
  }

  /// 弹系统通知权限对话框（Android 13+）
  Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    } catch (_) {}
  }

  Future<bool> openNotificationSettings() => _open('openNotificationSettings');

  Future<bool> openAutoStartSettings() => _open('openAutoStartSettings');

  Future<bool> openBatterySettings() => _open('openBatterySettings');

  Future<bool> openAppDetails() => _open('openAppDetails');

  /// 返回 false 表示该 ROM 没有这个页面，Dart 侧应提示用户手动去找
  Future<bool> _open(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } catch (_) {
      return false;
    }
  }
}

final keepAliveServiceProvider = Provider<KeepAliveService>(
  (Ref ref) => KeepAliveService(),
);
