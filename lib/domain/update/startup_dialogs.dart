import 'update_decision.dart';

/// 启动时可能弹的三种窗
enum StartupDialog {
  /// 远端驱动：有新版本，且版本文件里的 `policy` 要求提示（prompt / force）
  remoteUpdate,

  /// 本地兜底：远端拉不到时，靠本地常量 + major 比较告诉老用户"这版变了什么"
  localMajorUpdate,

  /// 首次使用手册（或手册内容改版）
  manual,
}

/// 启动时该弹哪些窗、按什么顺序（纯函数，宿主机可单测）。
///
/// 三条规则：
///   1. 远端要求提示 → **只**弹远端那份；本地大版本兜底让位（否则用户连看两个
///      内容几乎一样的弹窗）
///   2. 远端没要求（none / silentHint）→ 本地 major 变了才弹兜底
///   3. 手册永远排在最后：先讲"变了什么"，再教"怎么用"
List<StartupDialog> planStartupDialogs({
  required UpdateAction remoteAction,
  required bool localMajorDue,
  required bool manualDue,
}) {
  final List<StartupDialog> plan = <StartupDialog>[];

  final bool remoteWantsDialog = remoteAction == UpdateAction.showPrompt ||
      remoteAction == UpdateAction.forceUpdate;

  if (remoteWantsDialog) {
    plan.add(StartupDialog.remoteUpdate);
  } else if (localMajorDue) {
    plan.add(StartupDialog.localMajorUpdate);
  }

  if (manualDue) plan.add(StartupDialog.manual);
  return plan;
}
