import 'update_info.dart';

/// 启动时该做什么 —— 由 [decideUpdate] 算出来，UI 只按结果执行。
enum UpdateAction {
  /// 什么都不做（没有新版 / 拿不到版本信息 / 远端比当前旧）
  none,

  /// 有新版本，但只显示小红点（日常）
  silentHint,

  /// 有新版本，且远端要"下次启动弹一次"
  showPrompt,

  /// 有新版本，且远端要求强制更新
  forceUpdate,
}

/// 更新决策（纯函数，规格见 spec §14.1）。
///
/// 三条硬规则：
///   - [remote] 为 null（拉不到 / 脏数据）→ 什么都不做 —— **检查更新失败绝不打扰用户**
///   - 远端 versionCode **不大于**当前 → 什么都不做（相等不提示；更旧说明是回滚，忽略）
///   - [promptedVersionCode] 只用于 `prompt` 档：同一个版本弹过一次就不再弹；
///     `force` 档不受它影响（强制就是每次都要）
UpdateAction decideUpdate({
  required int currentVersionCode,
  required UpdateInfo? remote,
  required int? promptedVersionCode,
}) {
  if (remote == null) return UpdateAction.none;
  if (remote.versionCode <= currentVersionCode) return UpdateAction.none;

  switch (remote.policy) {
    case UpdatePolicy.silent:
      return UpdateAction.silentHint;
    case UpdatePolicy.force:
      return UpdateAction.forceUpdate;
    case UpdatePolicy.prompt:
      return promptedVersionCode == remote.versionCode
          ? UpdateAction.silentHint
          : UpdateAction.showPrompt;
  }
}
