import 'package:flutter/services.dart';

/// 调起系统安装器的结果
enum InstallStatus {
  /// 已经把安装界面拉起来了（用户接下来自己点「安装」）
  started,

  /// 还没授权"安装未知应用"，需要先去设置里打开
  needPermission,

  /// 这个系统/机型走不通（老版本、被 ROM 拦、路径不对…）
  unsupported,
}

/// 安装桥接 —— Dart 侧只负责"翻译"，真正的 Intent 在 `MainActivity.kt`。
///
/// ## 为什么返回值只有三种
///
/// Android 上第三方 App **不可能静默安装**：最多只能把系统安装器拉起来，
/// 用户在安装器里点一下。所以这里能给出的结论就是：
/// "拉起来了 / 缺权限 / 走不通" —— 界面按这三种分别提示。
///
/// ## 为什么不抛异常
///
/// 这条链路尽头是给用户"装新版本"。任何原生异常如果冒到界面，用户看到的是
/// "点了没反应"。所以全部吞掉并翻译成 [InstallStatus.unsupported]。
class ApkInstaller {
  ApkInstaller({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('pomodoro/installer');

  static const MethodChannel _defaultChannel =
      MethodChannel('pomodoro/installer');

  final MethodChannel _channel;

  /// 当前是否已被允许"安装未知应用"（API < 26 恒为 true）
  Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳到「安装未知应用」授权页（带本应用包名）
  Future<void> openInstallPermissionSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } catch (_) {
      // 跳不过去就只在界面上提示，用户自己去系统设置
    }
  }

  /// 调起系统安装器。成功只代表"安装界面起来了"，不代表装上了。
  Future<InstallStatus> install(String apkPath) async {
    try {
      final String? result = await _channel.invokeMethod<String>(
        'install',
        <String, Object?>{'path': apkPath},
      );
      switch (result) {
        case 'started':
          return InstallStatus.started;
        case 'needPermission':
          return InstallStatus.needPermission;
        default:
          return InstallStatus.unsupported;
      }
    } catch (_) {
      return InstallStatus.unsupported;
    }
  }

  /// 供测试与外部引用（避免 analyzer 认为常量没用）
  static MethodChannel get channel => _defaultChannel;
}
