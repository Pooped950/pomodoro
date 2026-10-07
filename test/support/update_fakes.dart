import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pomodoro/data/services/apk_downloader.dart';
import 'package:pomodoro/data/services/apk_installer.dart';
import 'package:pomodoro/data/services/update_service.dart';
import 'package:pomodoro/presentation/providers/update_provider.dart';

/// 更新相关测试共用的假件（放在 support/ 下，测试运行器不会把它当测试文件）

/// 'hello' 的 sha256
const String kHelloSha =
    '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

/// 一个永远对不上的 sha256（用来造"校验失败"）
final String kWrongSha = List<String>.filled(64, 'f').join();

class FakeUpdateStore implements UpdateStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

/// 造一份远端版本文件
String versionJson({
  required int versionCode,
  String versionName = '9.9.9',
  String policy = 'silent',
  String? sha256,
  int sizeBytes = 1024,
  List<String> notes = const <String>[],
  String? downloadPage = 'https://gitee.com/o/r',
}) =>
    jsonEncode(<String, Object?>{
      'versionCode': versionCode,
      'versionName': versionName,
      'apkUrl': 'https://gitee.com/o/r/raw/main/a.apk',
      'sha256': sha256 ?? kHelloSha,
      'sizeBytes': sizeBytes,
      'notes': notes,
      'policy': policy,
      'downloadPage': downloadPage,
    });

/// 假下载器：把内容直接写到目标路径，再按 [stream] 吐进度
class FakeDownloader extends ApkDownloader {
  FakeDownloader({
    this.content = 'hello',
    this.error,
    this.stream,
  });

  final String content;
  final Object? error;

  /// 想验"进度显示"时传一个自己可控的流
  final Stream<ApkDownloadProgress>? stream;

  int calls = 0;

  @override
  Stream<ApkDownloadProgress> download({
    required String url,
    required String destPath,
    required int expectedSize,
  }) async* {
    calls++;
    if (error != null) throw error!;
    final File f = File(destPath);
    await f.parent.create(recursive: true);
    f.writeAsStringSync(content);

    if (stream != null) {
      yield* stream!;
    } else {
      yield ApkDownloadProgress(
        received: content.length,
        total: content.length,
      );
    }
  }
}

class FakeInstaller extends ApkInstaller {
  FakeInstaller([this.status = InstallStatus.started]);

  final InstallStatus status;

  int installCalls = 0;
  int settingsCalls = 0;

  @override
  Future<InstallStatus> install(String apkPath) async {
    installCalls++;
    return status;
  }

  @override
  Future<void> openInstallPermissionSettings() async {
    settingsCalls++;
  }
}

/// 固定状态的假 notifier（界面测试用）
class FakeUpdateNotifier extends UpdateNotifier {
  FakeUpdateNotifier(this.initial);

  final UpdateState initial;

  @override
  UpdateState build() => initial;

  @override
  Future<void> checkNow() async {}

  @override
  Future<void> checkIfStale() async {}

  @override
  Future<void> startDownload() async {}

  @override
  Future<void> installDownloaded() async {}
}
