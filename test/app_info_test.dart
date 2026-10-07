import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/app_info.dart';

/// `app_info.dart` 手写了一份版本号（不引 package_info_plus），
/// 所以必须钉住它和 `pubspec.yaml` 永不漂移 —— Android 的 versionCode
/// 就是 pubspec 里 `+` 后面那个数，更新检查全靠它比对。
void main() {
  test('kAppVersion / kAppVersionCode 与 pubspec.yaml 一致', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? m =
        RegExp(r'^version:\s*([0-9.]+)\+(\d+)', multiLine: true)
            .firstMatch(pubspec);

    expect(m, isNotNull, reason: 'pubspec.yaml 里应有 version: x.y.z+N');
    expect(m!.group(1), kAppVersion, reason: 'kAppVersion 要跟 pubspec 的版本号一致');
    expect(int.parse(m.group(2)!), kAppVersionCode,
        reason: 'kAppVersionCode 要跟 pubspec 的 +N 一致（更新比较只认它）');
  });
}
