import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/data/services/apk_installer.dart';

/// 安装桥接的 Dart 侧 —— 它只是把原生结果翻译成三种状态。
/// 关键是**任何异常/未知返回值都不能抛出去**：这条链路尽头是"调起安装器"，
/// 抛异常会变成用户看到的"点了没反应"。
void main() {
  // 拦 MethodChannel 需要测试绑定先就位
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('pomodoro/installer');

  final List<MethodCall> calls = <MethodCall>[];

  void mock(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('canInstall 透传原值', () async {
    mock((MethodCall call) async => call.method == 'canInstall' ? true : null);

    expect(await ApkInstaller().canInstall(), isTrue);

    mock((MethodCall call) async => false);
    expect(await ApkInstaller().canInstall(), isFalse);
  });

  test('canInstall 原生抛错 → false（当作没权限），不往外抛', () async {
    mock((MethodCall call) async => throw PlatformException(code: 'boom'));

    expect(await ApkInstaller().canInstall(), isFalse);
  });

  test('install：原生说 needPermission → InstallStatus.needPermission', () async {
    mock((MethodCall call) async => 'needPermission');

    expect(await ApkInstaller().install('/tmp/a.apk'),
        InstallStatus.needPermission);
  });

  test('install：原生说 started → InstallStatus.started，并且把路径传下去了', () async {
    mock((MethodCall call) async => 'started');

    expect(await ApkInstaller().install('/tmp/a.apk'), InstallStatus.started);
    expect(calls.last.method, 'install');
    expect((calls.last.arguments as Map<Object?, Object?>)['path'], '/tmp/a.apk');
  });

  test('install：未知返回值 / 原生抛错 → unsupported（不抛异常）', () async {
    mock((MethodCall call) async => 'something-new');

    expect(await ApkInstaller().install('/tmp/a.apk'), InstallStatus.unsupported);

    mock((MethodCall call) async => throw PlatformException(code: 'boom'));
    expect(await ApkInstaller().install('/tmp/a.apk'), InstallStatus.unsupported);
  });

  test('openInstallPermissionSettings：调 openSettings，抛错也不外泄', () async {
    mock((MethodCall call) async => null);

    await ApkInstaller().openInstallPermissionSettings();
    expect(calls.last.method, 'openSettings');

    mock((MethodCall call) async => throw PlatformException(code: 'boom'));
    await ApkInstaller().openInstallPermissionSettings(); // 不该抛
  });
}
