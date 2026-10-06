import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 前台服务通道封装 —— MethodChannel("pomodoro/service")。
///
/// 只做薄薄的转发；异常全部吞掉转为安全空值，让"模拟器/测试环境没有原生层"
/// 时不影响纯 Dart 逻辑（MissingPluginException）。
class ForegroundService {
  static const MethodChannel _channel = MethodChannel('pomodoro/service');

  /// 注册"服务 → Dart"动作监听：用户在通知栏按暂停/继续/跳过时，
  /// 原生服务会回调 onServiceAction（app 在前台但被通知栏盖住时也能同步）。
  static void setActionHandler(void Function(String action)? handler) {
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onServiceAction') {
        final String action = call.arguments as String? ?? '';
        handler?.call(action);
      }
      return null;
    });
  }

  /// 启动或更新前台服务（服务不存在则启动，存在则换状态）
  Future<void> startOrUpdate(Map<String, Object?> state) async {
    try {
      await _channel.invokeMethod<void>('startOrUpdate', state);
    } on MissingPluginException {
      // 无原生层（测试环境）
    } catch (_) {
      // 服务起不来不阻塞计时（M3 止损线：降级为 App 内提醒）
    }
  }

  /// 停止前台服务并撤掉常驻通知
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  /// 拉取原生侧最新计时状态；服务未运行返回 null
  Future<Map<Object?, Object?>?> getState() async {
    try {
      return await _channel.invokeMethod<Map<Object?, Object?>>('getState');
    } catch (_) {
      return null;
    }
  }
}

final foregroundServiceProvider = Provider<ForegroundService>(
  (Ref ref) => ForegroundService(),
);
