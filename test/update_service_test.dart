import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/data/repositories/settings_repository.dart';
import 'package:pomodoro/data/services/update_service.dart';

/// 拉取远端版本文件的服务。
///
/// 全部用注入的假 fetcher，测试**不联网**；存储用内存假实现
/// （真 `SettingsRepository` 要 sqflite 数据库，宿主机测试里跑不起来）。
void main() {
  final String sha = List<String>.filled(64, 'b').join();

  String body({int code = 5, String policy = 'silent'}) => jsonEncode(<String, Object?>{
        'versionCode': code,
        'versionName': '2.1.0',
        'apkUrl': 'https://gitee.com/o/r/raw/main/a.apk',
        'sha256': sha,
        'sizeBytes': 1000,
        'notes': <String>['一'],
        'policy': policy,
      });

  late _FakeStore store;

  setUp(() => store = _FakeStore());

  UpdateService service(
    UpdateFetcher fetcher, {
    Duration minInterval = const Duration(minutes: 10),
    Duration timeout = const Duration(seconds: 5),
  }) =>
      UpdateService(
        store: store,
        fetcher: fetcher,
        endpoint: 'https://example.test/version.json',
        minInterval: minInterval,
        timeout: timeout,
      );

  test('正常拉到 → 返回远端信息，并把原文写进缓存', () async {
    final UpdateService s = service((String url) async => body());

    final info = await s.check(force: true);

    expect(info, isNotNull);
    expect(info!.versionCode, 5);
    expect(store.values[SettingsRepository.keyUpdateCachedJson], isNotNull);
    expect(store.values[SettingsRepository.keyUpdateLastCheckAt], isNotNull);
  });

  test('warmUp 后能从缓存读回上次那一条（离线也能显示）', () async {
    final UpdateService s = service((String url) async => body());

    await s.check(force: true);
    final UpdateService fresh = service((String url) async => null);
    await fresh.warmUp();

    expect(fresh.cached, isNotNull);
    expect(fresh.cached!.versionCode, 5);
    expect(fresh.lastCheckAt, isNotNull);
  });

  test('10 分钟内重复 check 不再发请求', () async {
    int calls = 0;
    final UpdateService s = service((String url) async {
      calls++;
      return body();
    });

    await s.check(force: true);
    await s.check();
    await s.check();

    expect(calls, 1);
  });

  test('force: true 忽略节流，每次都发请求（手动点「检查更新」）', () async {
    int calls = 0;
    final UpdateService s = service((String url) async {
      calls++;
      return body();
    });

    await s.check(force: true);
    await s.check(force: true);

    expect(calls, 2);
  });

  test('fetcher 抛异常 → 返回 null（静默失败），且不动上一次的缓存', () async {
    final UpdateService good = service((String url) async => body());
    await good.check(force: true);

    final UpdateService bad =
        service((String url) async => throw StateError('网络炸了'));
    final info = await bad.check(force: true);

    expect(info, isNull);
    await bad.warmUp();
    expect(bad.cached, isNotNull, reason: '上次成功的缓存不能被失败冲掉');
  });

  test('拉到脏 JSON → 返回 null，缓存不被覆盖', () async {
    final UpdateService good = service((String url) async => body());
    await good.check(force: true);

    final UpdateService dirty = service((String url) async => 'not json');
    expect(await dirty.check(force: true), isNull);
    await dirty.warmUp();
    expect(dirty.cached, isNotNull);
  });

  test('请求 URL 带时间戳参数（绕 Gitee 的 CDN 缓存）', () async {
    String? seen;
    final UpdateService s = service((String url) async {
      seen = url;
      return body();
    });

    await s.check(force: true);

    expect(seen, isNotNull);
    expect(seen, startsWith('https://example.test/version.json'));
    expect(seen, contains('t='));
  });

  test('fetcher 不返回（超时）→ 按失败处理，不会一直挂着', () async {
    final UpdateService s = service(
      (String url) => Completer<String?>().future, // 永不完成
      timeout: const Duration(milliseconds: 50),
    );

    final Stopwatch sw = Stopwatch()..start();
    final info = await s.check(force: true);
    sw.stop();

    expect(info, isNull);
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('失败也会记"上次检查时间"（离线时别疯狂重试）', () async {
    final UpdateService s =
        service((String url) async => throw StateError('offline'));

    await s.check(force: true);

    expect(store.values[SettingsRepository.keyUpdateLastCheckAt], isNotNull);
  });
}

class _FakeStore implements UpdateStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
