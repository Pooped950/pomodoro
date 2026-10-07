import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../domain/update/update_info.dart';
import '../../providers/update_provider.dart';
import '../../widgets/ambient_background.dart';
import '../../widgets/app_card.dart';

/// 「检查更新」页 —— 从「我的」最下面那一行进来。
///
/// ## 为什么是页面而不是弹窗
///
/// 这里要放四样东西：当前/最新版本、更新说明、下载进度、失败提示。
/// 弹窗装不下，而且下载过程需要一个"待得住"的地方。
/// 启动时的更新提示仍然是弹窗（`update_dialog.dart`）——那才是"扫一眼就走"的场景。
///
/// ## 两个回调为什么从外面传
///
/// [onUpdate]（下载并安装）和 [onOpenPage]（浏览器打开发布页）都涉及原生能力，
/// 由接线的地方注入：这样这一页在宿主机单测里能完整测四种状态，不用起原生通道。
class UpdatePage extends ConsumerWidget {
  const UpdatePage({super.key, this.onUpdate, this.onOpenPage});

  /// 点「立即更新」：下载 + 校验 + 调起安装器（Task 8 接）
  final Future<void> Function()? onUpdate;

  /// 点「打开发布页」（Task 7 的原生通道接）
  final Future<void> Function(String url)? onOpenPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final UpdateState state = ref.watch(updateStateProvider);
    final UpdateInfo? remote = state.remote;
    final bool hasNewer = state.hasNewer;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.tight,
                  AppSpacing.page,
                  AppSpacing.section,
                ),
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: '返回',
                      ),
                      Expanded(
                        child: Text('检查更新', style: text.titleMedium),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.tight),

                  AppCard(
                    child: Column(
                      children: <Widget>[
                        _VersionRow(label: '当前版本', value: 'v$kAppVersion'),
                        const SizedBox(height: AppSpacing.tight),
                        _VersionRow(
                          label: '最新版本',
                          value: remote == null ? '—' : 'v${remote.versionName}',
                        ),
                        if (state.checkedAt != null) ...<Widget>[
                          const SizedBox(height: AppSpacing.tight),
                          _VersionRow(
                            label: '上次检查',
                            value: _formatTime(state.checkedAt!),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.section),
                  if (state.checking)
                    const AppCard(
                      child: Row(
                        children: <Widget>[
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: AppSpacing.item),
                          Expanded(child: Text('正在检查…')),
                        ],
                      ),
                    )
                  else if (state.error != null)
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            state.error!,
                            style: text.bodyMedium?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.tight),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => ref
                                  .read(updateStateProvider.notifier)
                                  .checkNow(),
                              child: const Text('重试'),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (!hasNewer)
                    const AppCard(child: Text('已是最新')),

                  if (hasNewer && remote != null && remote.notes.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.section),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('这一版更新了什么', style: text.bodyMedium),
                          const SizedBox(height: AppSpacing.tight),
                          for (final String note in remote.notes)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: scheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      note,
                                      style: text.bodySmall?.copyWith(
                                        height: 1.5,
                                        color: scheme.onSurface
                                            .withValues(alpha: 0.75),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.section),
                  FilledButton(
                    onPressed: (hasNewer && onUpdate != null)
                        ? () => onUpdate!()
                        : null,
                    child: const Text('立即更新'),
                  ),
                  const SizedBox(height: AppSpacing.tight),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: () =>
                          ref.read(updateStateProvider.notifier).checkNow(),
                      child: const Text('重新检查'),
                    ),
                  ),
                  if (remote?.downloadPage != null)
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: onOpenPage == null
                            ? null
                            : () => onOpenPage!(remote!.downloadPage!),
                        child: const Text('打开发布页'),
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

  static String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: text.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
        Text(
          value,
          style: text.bodyMedium?.copyWith(
            fontFeatures: const <FontFeature>[FontFeature('tnum')],
          ),
        ),
      ],
    );
  }
}
