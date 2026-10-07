import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/motion_tokens.dart';
import '../../../data/services/background_image_store.dart';
import '../../../domain/settings/background_settings.dart';
import '../../providers/app_settings_provider.dart';
import '../../widgets/ambient_background.dart';
import '../../widgets/app_card.dart';
import '../../widgets/background_presets.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/motion_scope.dart';
import '../../widgets/pressable.dart';

/// 设置页的「背景」分组 —— 主页自定义背景。
///
/// ## 为什么带一个实时预览
///
/// 背景是**唯一一个"选错了整个主页都难看"的设置**，而且它的效果
/// 依赖玻璃叠加、依赖主题明暗，光看一个小色点根本判断不出来。
/// 所以这里直接嵌一块 [AmbientBackground]，并在上面浮一片玻璃 ——
/// 用户在这里看到的就是主页会变成的样子。
///
/// 这也符合这个项目的一贯做法：**视觉必须能当场核实，不能靠猜**。
class BackgroundSection extends ConsumerWidget {
  const BackgroundSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BackgroundSettings bg = ref.watch(backgroundSettingsProvider);
    final BackgroundSettingsNotifier notifier =
        ref.read(backgroundSettingsProvider.notifier);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('背景', style: text.bodyMedium),
          const SizedBox(height: 3),
          Text(
            '换掉主页背后的那一层。玻璃要透出背后的颜色才好看，'
            '所以背景换了，整个界面的观感都会跟着变。',
            style: text.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.5),
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.item),

          // 实时预览：就是主页的样子（背景 + 浮一片玻璃）
          const _BackgroundPreview(),
          const SizedBox(height: AppSpacing.item),

          _SwatchGrid(
            current: bg,
            onPickTheme: () => notifier.set(
              bg.copyWith(kind: BackgroundKind.theme),
            ),
            onPickPreset: (String id) => notifier.set(
              bg.copyWith(kind: BackgroundKind.preset, presetId: id),
            ),
          ),

          const SizedBox(height: AppSpacing.item),
          Divider(height: 1, color: scheme.onSurface.withValues(alpha: 0.06)),
          const SizedBox(height: 6),

          _ImageRow(
            settings: bg,
            onPick: () => _pickImage(context, ref),
            onRemove: () => _removeImage(context, ref),
          ),

          // 暗度与模糊只在"正在用照片"时才有意义 ——
          // 灰着不显示比显示一堆无效选项清楚
          if (bg.hasUsableImage && bg.kind == BackgroundKind.image) ...<Widget>[
            const SizedBox(height: 6),
            _DimSlider(
              value: bg.dim,
              onChanged: (double v) => notifier.update(
                (BackgroundSettings s) => s.copyWith(dim: v),
                persist: false,
              ),
              onChangeEnd: (double v) => notifier.update(
                (BackgroundSettings s) => s.copyWith(dim: v),
              ),
            ),
            _BlurSwitch(
              value: bg.blurred,
              onChanged: (bool v) => notifier.update(
                (BackgroundSettings s) => s.copyWith(blurred: v),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 选图 → 复制进应用私有目录 → 落库 → 删掉上一张。
  ///
  /// **顺序不能变**：先复制、再落库、最后删旧图。
  /// 反过来的话，一旦复制失败（空间不足 / 权限问题），
  /// 用户就把当前背景删了却什么也没换上。
  Future<void> _pickImage(BuildContext context, WidgetRef ref) async {
    final XFile? picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return; // 用户取消

    final BackgroundImageStore store = ref.read(backgroundImageStoreProvider);
    final BackgroundSettingsNotifier notifier =
        ref.read(backgroundSettingsProvider.notifier);
    final BackgroundSettings before = ref.read(backgroundSettingsProvider);

    try {
      final String path = await store.importFrom(picked.path);
      notifier.set(
        before.copyWith(kind: BackgroundKind.image, imagePath: path),
      );
      // 新图已经就位，这时删旧图才是安全的
      await store.replaceOld(before.imagePath, keepPath: path);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('这张图用不了：$e')),
      );
    }
  }

  /// 移除照片：删掉文件 + 清空路径 + 回到主题背景。
  Future<void> _removeImage(BuildContext context, WidgetRef ref) async {
    final BackgroundImageStore store = ref.read(backgroundImageStoreProvider);
    final BackgroundSettingsNotifier notifier =
        ref.read(backgroundSettingsProvider.notifier);
    final BackgroundSettings before = ref.read(backgroundSettingsProvider);

    notifier.set(
      before.copyWith(kind: BackgroundKind.theme, clearImagePath: true),
    );
    await store.replaceOld(before.imagePath);
  }
}

/// 实时预览：背景 + 一片浮在上面的玻璃。
class _BackgroundPreview extends StatelessWidget {
  const _BackgroundPreview();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.cardMedium),
      child: SizedBox(
        height: 116,
        child: Stack(
          children: <Widget>[
            // 这里**不传 settings**，直接画全局设置 ——
            // 预览要跟着设置实时变，传固定值就成了一张静态图
            const Positioned.fill(child: AmbientBackground()),

            // 浮一片玻璃：让用户看到"背景变了之后玻璃是什么样"。
            // 玻璃看不见背景的话，换背景这件事就没有意义了。
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: GlassSurface(
                radius: AppRadius.chip + 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.timer_outlined,
                        size: 16,
                        color: scheme.onSurface.withValues(alpha: 0.75),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '玻璃会透出背景的颜色',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 色卡网格：第一格是「跟随主题」，后面是预设色卡。
class _SwatchGrid extends StatelessWidget {
  const _SwatchGrid({
    required this.current,
    required this.onPickTheme,
    required this.onPickPreset,
  });

  final BackgroundSettings current;
  final VoidCallback onPickTheme;
  final ValueChanged<String> onPickPreset;

  @override
  Widget build(BuildContext context) {
    final bool themeSelected = current.kind == BackgroundKind.theme;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        _Swatch(
          label: '跟随主题',
          selected: themeSelected,
          // 跟随主题没法用固定颜色表示，画一个"主题色三色环"示意
          colors: null,
          onTap: onPickTheme,
        ),
        for (final BackgroundPreset p in kBackgroundPresets)
          _Swatch(
            label: p.name,
            selected: current.kind == BackgroundKind.preset &&
                current.presetId == p.id,
            colors: presetSwatchColors(p),
            onTap: () => onPickPreset(p.id),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final bool selected;

  /// null = 「跟随主题」，用主题色画
  final List<Color>? colors;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final Motion motion = MotionScope.of(context);

    final List<Color> fill = colors ??
        <Color>[scheme.primary, scheme.tertiary];

    return SizedBox(
      width: 58,
      child: Column(
        children: <Widget>[
          Pressable(
            onTap: onTap,
            scale: 0.93,
            child: AnimatedContainer(
              duration: motion.standard,
              curve: MotionTokens.emphasized,
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: fill,
                ),
                // 选中态：外圈描边 + 一点外发光，而不是只加个对勾 ——
                // 色卡上叠对勾会挡住颜色本身
                border: Border.all(
                  color: selected
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.08),
                  width: selected ? 2.5 : 1,
                ),
                boxShadow: selected
                    ? <BoxShadow>[
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: selected
                  ? Icon(
                      Icons.check_rounded,
                      size: 20,
                      // 对勾用白色 + 阴影保证在任何底色上都看得见
                      color: Colors.white,
                      shadows: <Shadow>[
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 3,
                        ),
                      ],
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(
              fontSize: 11,
              color: selected
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.55),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// 「从相册选择」/「移除照片」那一行
class _ImageRow extends StatelessWidget {
  const _ImageRow({
    required this.settings,
    required this.onPick,
    required this.onRemove,
  });

  final BackgroundSettings settings;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    final bool usingImage = settings.kind == BackgroundKind.image &&
        settings.hasUsableImage;

    return Row(
      children: <Widget>[
        Icon(
          Icons.photo_library_outlined,
          size: 19,
          color: scheme.onSurface.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('自己的照片', style: text.bodyMedium),
              const SizedBox(height: 2),
              Text(
                usingImage
                    ? _fileName(settings.imagePath!)
                    : '从相册选一张',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(
                  color: usingImage
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (settings.imagePath != null)
          TextButton(
            onPressed: onRemove,
            child: const Text('移除'),
          ),
        TextButton(
          onPressed: onPick,
          child: Text(usingImage ? '换一张' : '选择'),
        ),
      ],
    );
  }

  /// 只显示文件名，不显示完整路径 —— 路径一长就把整行挤爆了
  static String _fileName(String path) {
    final int slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}

/// 暗度滑动条
class _DimSlider extends StatelessWidget {
  const _DimSlider({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text('压暗程度', style: text.bodyMedium)),
            Text(
              '${(value * 100).round()}%',
              style: text.bodySmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
                fontFeatures: const <FontFeature>[FontFeature('tnum')],
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '照片太亮时把界面文字压得看不清，就调大这里',
          style: text.bodySmall?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: scheme.primary.withValues(alpha: 0.85),
            inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.10),
            thumbColor: scheme.primary,
            overlayColor: scheme.primary.withValues(alpha: 0.12),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
          ),
          child: Slider(
            value: value.clamp(
              BackgroundSettings.minDim,
              BackgroundSettings.maxDim,
            ),
            min: BackgroundSettings.minDim,
            max: BackgroundSettings.maxDim,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}

/// 模糊开关
class _BlurSwitch extends StatelessWidget {
  const _BlurSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('模糊照片', style: text.bodyMedium),
              const SizedBox(height: 2),
              Text(
                '化开细节，背景更耐看、玻璃层次也更明显',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
