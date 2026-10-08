import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart';
import '../../core/theme/design_tokens.dart';
import '../providers/update_provider.dart';
import 'pressable.dart';

/// 「关于」页里的一行：检查更新。
///
/// ## 三种副标题对应三种状态
///   - 还没拿到版本信息 → `当前版本 v2.0.2`
///   - 已经是最新 → `已是最新 · v2.0.2`
///   - 有新版本 → `有新版本 v2.1.0` + 小红点
///
/// 小红点用 [dotKey] 定位，界面测试直接找它（比找颜色稳）。
///
/// ## 为什么在这里发静默检查
///
/// 用户能看到这一行的地方就是「关于」页，所以"进页面顺手看一眼有无新版"
/// 放在这个组件的 initState 最自然。真正的节流在 `UpdateService` 里（10 分钟），
/// 这里不需要再判一次。
///
/// ⚠️ 2026-10-07 用户要求：这一行从「我的」一级页**挪进「关于」二级页** ——
/// 挪动只改了挂载点，组件本身没变（挂哪儿都能用）。
class UpdateRow extends ConsumerStatefulWidget {
  const UpdateRow({super.key, this.onTap});

  /// 点整行的动作（进「检查更新」页）；由接线处给
  final VoidCallback? onTap;

  /// 小红点（有新版本时出现）——界面测试用它定位
  static const Key dotKey = Key('update-row-dot');

  @override
  ConsumerState<UpdateRow> createState() => _UpdateRowState();
}

class _UpdateRowState extends ConsumerState<UpdateRow> {
  @override
  void initState() {
    super.initState();
    // 首帧之后再发请求：不在 build 里做副作用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(updateStateProvider.notifier).checkIfStale();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final UpdateState state = ref.watch(updateStateProvider);

    return Pressable(
      onTap: widget.onTap ?? () {},
      highlightColor: scheme.primary.withValues(alpha: 0.07),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.item,
          14,
          AppSpacing.tight,
          14,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.system_update_alt_rounded,
              size: 20,
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('检查更新', style: text.bodyMedium),
                  const SizedBox(height: 3),
                  Text(
                    _subtitle(state),
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.5),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (state.hasNewer)
              Container(
                key: UpdateRow.dotKey,
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: scheme.error,
                  shape: BoxShape.circle,
                ),
              ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: scheme.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  static String _subtitle(UpdateState state) {
    if (state.hasNewer) return '有新版本 v${state.remote!.versionName}';
    if (state.remote != null) return '已是最新 · v$kAppVersion';
    // 还没拿到（或拉取失败）：显示当前版本就好，失败不打扰
    return '当前版本 v$kAppVersion';
  }
}
