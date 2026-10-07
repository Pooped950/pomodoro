import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/app_info.dart';
import 'package:pomodoro/data/repositories/settings_repository.dart';
import 'package:pomodoro/data/services/update_service.dart';
import 'package:pomodoro/domain/update/update_decision.dart';
import 'package:pomodoro/presentation/providers/update_provider.dart';

/// 更新状态 provider —— UI 全靠它，所以"三种 policy 各算什么 action"
/// 和"检查失败时缓存还在不在"必须钉住。
void main() {
  final String sha = List<String>.filled(64, 'c').join();

  String body({required int code, required String policy}) =>
      jsonEncode(<String, Object?>{
        'versionCode': code,
        'versionName': '9.9.9',
        'apkUrl': 'https://gitee.com/o/r/raw/main/a.apk',
        'sha256': sha,
        'sizeBytes': 1000,
        'notes': <String>['新版说明'],
        'policy': policy,
      });

  late _FakeStore store;

  setUp(() => store = _FakeStore());

  UpdateService serviceThatFails() => UpdateService(
        store: store,
        fetcher: (String url) async => throw StateError('offline'),
        endpoint: 'https://example.test/version.json',
      );

  UpdateService serviceWith({required int code, required String policy}) =>
      UpdateService(
        store: store,
        fetcher: (String url) async => body(code: code, policy: policy),
        endpoint: 'https://example.test/version.json',
      );

  Future<ProviderContainer> containerFor(UpdateService service) async {
    final ProviderContainer c = ProviderContainer(
      overrides: [updateServiceProvider.overrideWithValue(service)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('checkNow 成功后：action 按 policy 算（silent / prompt / force）', () async {
    final int newer = kAppVersionCode + 1;

    final ProviderContainer silent =
        await containerFor(serviceWith(code: newer, policy: 'silent'));
    await silent.read(updateStateProvider.notifier).checkNow();
    expect(silent.read(updateStateProvider).action, UpdateAction.silentHint);

    final ProviderContainer prompt =
        await containerFor(serviceWith(code: newer, policy: 'prompt'));
    await prompt.read(updateStateProvider.notifier).checkNow();
    expect(prompt.read(updateStateProvider).action, UpdateAction.showPrompt);

    final ProviderContainer force =
        await containerFor(serviceWith(code: newer, policy: 'force'));
    await force.read(updateStateProvider.notifier).checkNow();
    expect(force.read(updateStateProvider).action, UpdateAction.forceUpdate);
  });

  test('checkNow 成功：remote / checkedAt 有值，error 为空，checking 归位', () async {
    final ProviderContainer c = await containerFor(
        serviceWith(code: kAppVersionCode + 1, policy: 'silent'));

    await c.read(updateStateProvider.notifier).checkNow();
    final UpdateState s = c.read(updateStateProvider);

    expect(s.remote, isNotNull);
    expect(s.checkedAt, isNotNull);
    expect(s.error, isNull);
    expect(s.checking, isFalse);
  });

  test('markPrompted：记下这个版本，action 从 showPrompt 降级成小红点', () async {
    final ProviderContainer c = await containerFor(
        serviceWith(code: kAppVersionCode + 1, policy: 'prompt'));
    final UpdateNotifier n = c.read(updateStateProvider.notifier);

    await n.checkNow();
    expect(c.read(updateStateProvider).action, UpdateAction.showPrompt);

    await n.markPrompted();

    expect(c.read(updateStateProvider).action, UpdateAction.silentHint);
    expect(store.values[SettingsRepository.keyUpdatePromptedVersionCode],
        '${kAppVersionCode + 1}');
  });

  test('检查失败 → error 非空，但 remote 保留上次成功的缓存', () async {
    // 先成功一次，把缓存写进同一个 store
    final UpdateService good =
        serviceWith(code: kAppVersionCode + 1, policy: 'silent');
    await good.check(force: true);

    final ProviderContainer c = await containerFor(serviceThatFails());
    final UpdateNotifier n = c.read(updateStateProvider.notifier);

    await n.checkNow();
    final UpdateState s = c.read(updateStateProvider);

    expect(s.error, isNotNull);
    expect(s.remote, isNotNull, reason: '上次看到的版本不能因为一次失败就没了');
    expect(s.remote!.versionCode, kAppVersionCode + 1);
  });

  test('远端不比当前新 → action 是 none（不打扰）', () async {
    final ProviderContainer c = await containerFor(
        serviceWith(code: kAppVersionCode, policy: 'force'));

    await c.read(updateStateProvider.notifier).checkNow();

    expect(c.read(updateStateProvider).action, UpdateAction.none);
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
