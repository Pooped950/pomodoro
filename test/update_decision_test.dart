import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/update/update_decision.dart';
import 'package:pomodoro/domain/update/update_info.dart';

/// 更新决策矩阵（spec §14.1）—— 启动时"弹不弹、弹哪一档"全靠这个纯函数。
void main() {
  final String sha = List<String>.filled(64, 'a').join();

  UpdateInfo remote({required int code, UpdatePolicy policy = UpdatePolicy.silent}) =>
      UpdateInfo(
        versionCode: code,
        versionName: '9.9.9',
        apkUrl: 'https://gitee.com/a/b.apk',
        sha256: sha,
        sizeBytes: 1024,
        policy: policy,
      );

  test('远端不比当前新（相等/更旧）→ none', () {
    expect(
        decideUpdate(
            currentVersionCode: 4,
            remote: remote(code: 4),
            promptedVersionCode: null),
        UpdateAction.none);
    expect(
        decideUpdate(
            currentVersionCode: 4,
            remote: remote(code: 3),
            promptedVersionCode: null),
        UpdateAction.none);
  });

  test('远端拿不到（null）→ none：检查失败绝不打扰', () {
    expect(
        decideUpdate(
            currentVersionCode: 4, remote: null, promptedVersionCode: null),
        UpdateAction.none);
  });

  test('policy=silent + 有新版本 → 只给小红点', () {
    expect(
        decideUpdate(
            currentVersionCode: 4,
            remote: remote(code: 5),
            promptedVersionCode: null),
        UpdateAction.silentHint);
    expect(
        decideUpdate(
            currentVersionCode: 4,
            remote: remote(code: 5),
            promptedVersionCode: 5),
        UpdateAction.silentHint);
  });

  test('policy=prompt：没弹过→showPrompt；弹过这个版本→只给小红点', () {
    final UpdateInfo r = remote(code: 5, policy: UpdatePolicy.prompt);

    expect(
        decideUpdate(
            currentVersionCode: 4, remote: r, promptedVersionCode: null),
        UpdateAction.showPrompt);
    expect(
        decideUpdate(currentVersionCode: 4, remote: r, promptedVersionCode: 5),
        UpdateAction.silentHint);
    // 弹过的是更老的版本 → 新版本还要弹
    expect(
        decideUpdate(currentVersionCode: 4, remote: r, promptedVersionCode: 4),
        UpdateAction.showPrompt);
  });

  test('policy=force：不管弹没弹过都强制', () {
    final UpdateInfo r = remote(code: 5, policy: UpdatePolicy.force);

    expect(
        decideUpdate(
            currentVersionCode: 4, remote: r, promptedVersionCode: null),
        UpdateAction.forceUpdate);
    expect(
        decideUpdate(currentVersionCode: 4, remote: r, promptedVersionCode: 5),
        UpdateAction.forceUpdate);
  });
}
