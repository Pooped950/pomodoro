import 'package:flutter/material.dart';

import '../../../core/app_info.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/motion_tokens.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/motion_scope.dart';

/// 当前版本相对 [seenVersion] 是否要弹「大版本更新」弹窗。
///
/// 规则（2026-10-07 用户要求：**大版本更新才弹**，小版本/补丁不烦人）：
///   - 比较的是 **major 段**（`2.0.0` 的 `2`）：seen 的 major 更小 → 要弹
///   - [seenVersion] 为 null 或认不出 → **不弹**（全新安装走手册，
///     不该再叠一个更新弹窗；脏数据宁可少弹不要错弹）
///
/// 纯函数，宿主机可直接单测。
bool shouldShowMajorUpdateDialog(String? seenVersion, String currentVersion) {
  final int? seenMajor = _majorOf(seenVersion);
  final int? currentMajor = _majorOf(currentVersion);
  if (seenMajor == null || currentMajor == null) return false;
  return seenMajor < currentMajor;
}

int? _majorOf(String? version) {
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

/// 大版本更新弹窗 —— 升级后**首次启动**弹一次，居中玻璃卡。
///
/// 和首启手册同一个视觉语言（居中 + 玻璃 + 中心缩放），但只有一页：
/// 大版本更新是"告诉你得到了什么"，不是"教你用"，不该把整本手册再弹一遍。
Future<void> showUpdateDialog(BuildContext context) {
  final Motion motion = MotionScope.resolve(context);

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭更新说明',
    barrierColor: Colors.black.withValues(alpha: 0.30),
    transitionDuration: motion.pageEnter,
    pageBuilder: (
      BuildContext _,
      Animation<double> _,
      Animation<double> _,
    ) =>
        const UpdateDialogBody(),
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
  const UpdateDialogBody({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Center(
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
                          'v$kAppVersion 更新了什么',
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
                          for (final String note in kMajorUpdateNotes)
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
    );
  }
}
