import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/update/startup_dialogs.dart';
import 'package:pomodoro/domain/update/update_decision.dart';

/// 启动时"弹哪些窗、什么顺序"—— 这条规则最容易出的两个问题：
///   1. 远端更新弹窗和本地大版本兜底**同时弹**（用户连着看两个几乎一样的窗）
///   2. 远端拉不到时**什么都不弹**（老用户升级后看不到"这版变了什么"）
void main() {
  List<StartupDialog> plan({
    UpdateAction remote = UpdateAction.none,
    bool localMajorDue = false,
    bool manualDue = false,
  }) =>
      planStartupDialogs(
        remoteAction: remote,
        localMajorDue: localMajorDue,
        manualDue: manualDue,
      );

  test('远端要求弹（prompt）→ 只弹远端那份，本地兜底不再叠', () {
    expect(
      plan(remote: UpdateAction.showPrompt, localMajorDue: true),
      <StartupDialog>[StartupDialog.remoteUpdate],
    );
  });

  test('远端要求强制（force）→ 同样只弹远端那份', () {
    expect(
      plan(remote: UpdateAction.forceUpdate, localMajorDue: true),
      <StartupDialog>[StartupDialog.remoteUpdate],
    );
  });

  test('远端没说要弹 + 本地 major 变了 → 走本地兜底（离线也有交代）', () {
    expect(
      plan(localMajorDue: true),
      <StartupDialog>[StartupDialog.localMajorUpdate],
    );
  });

  test('远端只给小红点（silentHint）→ 不算"要弹"，仍可走本地兜底', () {
    expect(
      plan(remote: UpdateAction.silentHint, localMajorDue: true),
      <StartupDialog>[StartupDialog.localMajorUpdate],
    );
  });

  test('手册该弹时排在最后（先讲"变了什么"，再教"怎么用"）', () {
    expect(
      plan(remote: UpdateAction.showPrompt, manualDue: true),
      <StartupDialog>[StartupDialog.remoteUpdate, StartupDialog.manual],
    );
    expect(
      plan(localMajorDue: true, manualDue: true),
      <StartupDialog>[StartupDialog.localMajorUpdate, StartupDialog.manual],
    );
  });

  test('什么都不该弹 → 空计划', () {
    expect(plan(), isEmpty);
  });
}
