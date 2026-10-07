import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_info.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/motion_tokens.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/motion_scope.dart';

/// 启动时该不该弹「大版本更新说明」。
///
/// 规则（2026-10-07 用户要求：**大版本更新才弹**，小版本/补丁不烦人）：
///   - [isFreshInstall]（手册从没弹过 = 全新安装）→ **不弹**：手册讲得更全，
///     不该再叠一个弹窗
///   - 否则比较 **major 段**（`2.0.0` 的 `2`）：见过的 major 更小 → 弹
///   - [seenVersion] 为 `null` = **这台机器上还没有这个键**：本功能是 2.0.0 才加的，
///     从 1.8.0 升上来的用户读出来就是 null —— 对老用户等于"没见过" → 弹
///   - 认不出的脏数据（`abc`）→ 不弹：宁可少弹，不要错弹
///
/// ⚠️ 2026-10-07 真机实测踩到的坑（见交接文档 §4.8）：早先的版本把 `null` 一律当
/// "全新安装"直接不弹，结果 **1.8.0 → 2.0.0 这条真实升级路径永远不会弹更新说明**。
/// 「全新安装」的判据只能是「手册看没看过」，**不能**用"这个键存不存在"。
///
/// 纯函数，宿主机可直接单测。
bool shouldShowMajorUpdateDialog({
  required bool isFreshInstall,
  required String? seenVersion,
  required String currentVersion,
}) {
  if (isFreshInstall) return false;
  final int? currentMajor = majorVersionOf(currentVersion);
  if (currentMajor == null) return false;
  if (seenVersion == null) return true;
  final int? seenMajor = majorVersionOf(seenVersion);
  if (seenMajor == null) return false;
  return seenMajor < currentMajor;
}

/// 取版本号的 major 段（`2.0.1` → `2`）；`null` 或认不出返回 `null`。
int? majorVersionOf(String? version) {
  if (version == null) return null;
  final String major = version.trim().split('.').first;
  return int.tryParse(major);
}

/// v2.0.0 的更新内容（用户语言，不写实现术语）。
///
/// ⚠️ 发大版本时和版本号一起换：这里说的是"这次更新你得到了什么"。
const List<String> kMajorUpdateNotes = <String>[
  '课表导入大升级：识别更准 —— 跨节的课、被认错的字都会自动修正；'
      '支持直接粘贴官方作息表，每节课时间精确到分',
  '课表能直接操作了：每节课右上角三个点 —— 本周隐藏、永久删除、加一节课；'
      '点空白格也能加',
  '更流畅：申请屏幕最高刷新率，整体动画更丝滑',
  '时间排不下会当场提醒，上午/下午的节数可以自己改',
];

/// 更新说明弹窗。
///
/// 两种来源、两种分量：
///   - **本地兜底**：不传参数 —— 用 [kMajorUpdateNotes]，升级后首次启动弹一次（可关）
///   - **远端驱动**：传 [version] / [notes]（远端 `version.json` 里的原文）。
///     [force] 为 true 时**关不掉**（遮罩、返回键都无效），只能「立即更新」或「退出」
///
/// 视觉语言和首启手册一致（居中 + 玻璃 + 中心缩放），但只有一页：
/// 更新说明是"告诉你得到了什么"，不是"教你用"。
Future<void> showUpdateDialog(
  BuildContext context, {
  String? version,
  List<String>? notes,
  bool force = false,
  VoidCallback? onUpdate,
}) {
  final Motion motion = MotionScope.resolve(context);

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: !force,
    barrierLabel: '关闭更新说明',
    barrierColor: Colors.black.withValues(alpha: 0.30),
    transitionDuration: motion.pageEnter,
    pageBuilder: (
      BuildContext _,
      Animation<double> _,
      Animation<double> _,
    ) =>
        UpdateDialogBody(
      version: version,
      notes: notes,
      force: force,
      onUpdate: onUpdate,
    ),
    transitionBuilder: (
      BuildContext _,
      Animation<double> animation,
      Animation<double> _,
      Widget child,
    ) {
      final Animation<double> curved = CurvedAnimation(
        parent: animation,
        curve: MotionTokens.emphasized,
        reverseCurve: MotionTokens.emphasizedIn,
      );
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: const Interval(0, 0.5, curve: Curves.easeOut),
        ),
        child: ScaleTransition(
          alignment: Alignment.center,
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class UpdateDialogBody extends StatelessWidget {
  const UpdateDialogBody({
    super.key,
    this.version,
    this.notes,
    this.force = false,
    this.onUpdate,
  });

  /// 远端版本号（不传就用当前 App 版本）
  final String? version;

  /// 远端更新说明（不传就用本地常量 [kMajorUpdateNotes]）
  final List<String>? notes;

  /// 强制更新：关不掉，只能去更新或退出
  final bool force;

  /// 点「立即更新」干什么（由外壳给：进「检查更新」页）
  final VoidCallback? onUpdate;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final List<String> bullets = notes ?? kMajorUpdateNotes;

    return PopScope(
      // force 档：系统返回键也不能把它关掉
      canPop: !force,
      child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: kMaxContentWidth,
            maxHeight: MediaQuery.of(context).size.height * 0.76,
          ),
          // 必须有 Material 祖先：showGeneralDialog 不自带（黄色下划线的坑，
          // 见 manual_dialog 同款注释）
          child: Material(
            type: MaterialType.transparency,
            child: GlassSurface(
              radius: AppRadius.card,
              padding: const EdgeInsets.all(AppSpacing.item),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: 20,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'v${version ?? kAppVersion} 更新了什么',
                          style: text.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.item),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (final String note in bullets)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.tight),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(
                                      Icons.check_circle_rounded,
                                      size: 15,
                                      color: scheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      note,
                                      style: text.bodyMedium?.copyWith(
                                        height: 1.55,
                                        color: scheme.onSurface
                                            .withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.tight),
                  if (force) ...<Widget>[
                    // 强制档：只能去更新，或者退出 App（不给"以后再说"）
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onUpdate,
                        child: const Text('立即更新'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.tight),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: () => SystemNavigator.pop(),
                        child: const Text('退出'),
                      ),
                    ),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('开始使用'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
