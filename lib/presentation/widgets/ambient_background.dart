import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design_tokens.dart';
import '../../domain/settings/background_settings.dart';
import '../providers/app_settings_provider.dart';
import 'background_presets.dart';
import 'motion_scope.dart';

/// 环境背景 —— 柔光玻璃「感知环境颜色」的对象，也是主页自定义背景的落点。
///
/// ## 为什么必须有这一层
///
/// 这是本项目踩过的一个真实坑：一开始界面背景是一整片纯白，
/// 玻璃导航条盖上去之后**看起来和普通白条完全一样** ——
/// 因为白玻璃折射白背景，结果还是白。
///
/// 玻璃要"看得见"，前提是**背后有东西可折射**。这一层负责铺出那个"东西"。
///
/// ## 三种背景
///
/// | 类型 | 画什么 | 怎么来的 |
/// |---|---|---|
/// | [BackgroundKind.theme] | 主题色光斑（默认） | 跟随动态取色，用户不用管 |
/// | [BackgroundKind.preset] | 预设色卡的光斑 | 用户从设置里挑一个 |
/// | [BackgroundKind.image] | 相册照片 + 可调暗度/模糊 | 用户选自己的图 |
///
/// 三种都是**纯绘制**（除图片外），不用 BackdropFilter、不用 ImageFilter，
/// 性能开销可以忽略。图片那种多一层解码 + 可选的一次高斯模糊。
///
/// ## 图片模式下为什么还要压暗
///
/// 背景图是**用户随便选的** —— 可能是雪景（很亮）也可能是夜景。
/// 不做压暗的话，浅色玻璃和深色文字在亮图上会直接看不清。
/// 所以压暗不是一个装饰项，而是保证"背景换了、界面还能读"的必要措施。
class AmbientBackground extends ConsumerWidget {
  const AmbientBackground({
    super.key,
    this.child,
    this.strength,
    this.settings,
  });

  final Widget? child;

  /// 覆盖环境色强度，默认按当前主题明暗取
  /// [GlassTokens.ambientStrengthLight] / [GlassTokens.ambientStrengthDark]
  final double? strength;

  /// 覆盖背景设置。**给预览用**（设置页里要同时画出"当前选中的背景"，
  /// 而那时全局设置可能还没提交）。null = 读全局设置。
  final BackgroundSettings? settings;

  /// 光晕配置：中心点（相对坐标）+ 半径（占短边比例）+ 透明度 + 调色板下标
  ///
  /// 最后一列是**用哪个颜色** —— 四个光斑用不同颜色而不是同一种，
  /// 玻璃盖上去折射出来的色彩层次才丰富（液态玻璃"鲜艳透光"的观感来源）。
  static const List<List<double>> _blobs = <List<double>>[
    <double>[0.14, 0.04, 0.46, 0.34, 0],
    <double>[0.90, 0.16, 0.38, 0.22, 1],
    <double>[0.64, 0.50, 0.52, 0.18, 2],
    <double>[0.38, 1.04, 0.62, 0.30, 0],
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isDark = scheme.brightness == Brightness.dark;

    final BackgroundSettings bg =
        settings ?? ref.watch(backgroundSettingsProvider);
    // 用 effectiveKind 而不是 kind：选了图片但文件丢了 → 回退主题背景，
    // 而不是画一块白板（用户会以为 App 坏了）
    final BackgroundKind kind = bg.effectiveKind;

    final BackgroundPreset? preset =
        kind == BackgroundKind.preset ? presetById(bg.presetId) : null;

    // 预设色卡单独放大强度：主题背景是"氛围"要克制，
    // 而预设是用户主动选的 —— 看不出变化等于功能没生效（见 presetStrengthBoost 注释）
    final double effectiveStrength = resolveAmbientStrength(
      isDark: isDark,
      preset: preset,
      override: strength,
    );

    final List<Color> palette;
    if (preset != null) {
      palette = preset.colors;
    } else {
      palette = <Color>[scheme.primary, scheme.tertiary, scheme.secondary];
    }

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            // ⚠️ RepaintBoundary 是**性能关键**，不是可有可无的装饰。
            //
            // 这一层要画 4 个**全屏**径向渐变。如果不隔离，那么页面里任何
            // 一点点重绘（滚动、动画、按压反馈）都会顺着渲染树往上冒到 Stack，
            // 把这一整块重新光栅化一遍 —— 120Hz 下每帧只有 8.3ms，
            // 4 个全屏 shader pass 直接爆预算。
            //
            // 2026-10-06 真机实测「我的页帧率明显不足 120Hz」就是这类问题。
            // 加了边界之后它只在参数真的变了（换背景/切深浅色）才重画，
            // 滚动时它是合成器里的一张现成纹理，几乎不花时间。
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _AmbientPainter(
                  surface: scheme.surface,
                  palette: palette,
                  strength: effectiveStrength,
                  // 图片模式不画光斑：照片自己就是"背后那层东西"，
                  // 再叠光斑会把照片糊得看不清
                  drawBlobs: kind != BackgroundKind.image,
                ),
              ),
            ),
          ),
        ),

        if (kind == BackgroundKind.image)
          Positioned.fill(
            child: IgnorePointer(
              // 同理：图片那层叠了高斯模糊，更贵，必须隔离
              child: RepaintBoundary(
                child: _ImageBackgroundLayer(settings: bg),
              ),
            ),
          ),

        ?child,
      ],
    );
  }
}

/// 算出**实际生效**的环境色强度。
///
/// 抽成纯函数是为了能单测一条重要的不变量：
/// **预设色卡必须明显强于主题背景** —— 预设是用户主动选的，
/// 看不出变化等于功能没生效（2026-10-06 实测踩到，整图平均色只差 2/255）。
///
/// [override] 是外部显式指定的强度（预览/调试用），给了就以它为准。
double resolveAmbientStrength({
  required bool isDark,
  required BackgroundPreset? preset,
  required double? override,
}) {
  if (override != null) return override;

  final double base = isDark
      ? GlassTokens.ambientStrengthDark
      : GlassTokens.ambientStrengthLight;

  if (preset == null) return base;
  return base * GlassTokens.presetStrengthBoost * preset.strengthScale;
}

/// 相册照片背景：照片 + 可选模糊 + 可调压暗。
class _ImageBackgroundLayer extends StatelessWidget {
  const _ImageBackgroundLayer({required this.settings});

  final BackgroundSettings settings;

  /// 模糊半径。16 是"细节化开、但还看得出是什么照片"的量级 ——
  /// 再大就变成一团色块，用户会觉得"我选的图怎么没了"
  static const double _blurSigma = 16;

  @override
  Widget build(BuildContext context) {
    final String path = settings.imagePath!;

    Widget image = Image.file(
      File(path),
      fit: BoxFit.cover,
      // 限制解码尺寸：相册原图动辄 4000px 宽，整张解码进内存要几十 MB，
      // 再叠一次全屏高斯模糊会直接卡住
      cacheWidth: BackgroundSettings.imageDecodeWidth,
      // 换图时不闪白：新图解码完成前继续显示旧帧
      gaplessPlayback: true,
      // 文件被外部删掉时不要抛异常（上层会露出底色，不会白屏）
      errorBuilder: (
        BuildContext _,
        Object _,
        StackTrace? _,
      ) =>
          const SizedBox.expand(),
      frameBuilder: (
        BuildContext context,
        Widget child,
        int? frame,
        bool wasSynchronouslyLoaded,
      ) {
        // 解码是异步的：直接换上去会"啪"地跳出来，淡入才自然
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: MotionScope.of(context).standard,
          curve: Curves.easeOut,
          child: child,
        );
      },
    );

    if (settings.blurred) {
      // 先放大一点点再模糊：高斯模糊会采样边界外的像素，
      // 不放大就会在屏幕四周出现一圈发虚的白边
      //
      // ⚠️ 外面套 [RepaintBoundary]（2026-10-09 性能优化）：
      // 高斯模糊是**实时算**的，每次重绘都要把整屏重新采样一遍 ——
      // 低端机 GPU 填充率本来就紧张，一次多余的模糊就是一次肉眼可见的卡。
      // 用边界把它圈起来，只有模糊层自己变脏时才重绘。
      image = RepaintBoundary(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: _blurSigma,
            sigmaY: _blurSigma,
          ),
          child: Transform.scale(scale: 1.08, child: image),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        image,
        // 压暗层：保证前景文字与玻璃在任何照片上都读得清
        ColoredBox(
          color: Colors.black.withValues(alpha: settings.dim),
        ),
      ],
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({
    required this.surface,
    required this.palette,
    required this.strength,
    this.drawBlobs = true,
  });

  final Color surface;

  /// 可用颜色（主题色 或 预设色卡），由 [AmbientBackground._blobs] 最后一列选
  final List<Color> palette;

  final double strength;

  /// false 时只铺底色（图片模式用）
  final bool drawBlobs;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    // 底色：保证整块区域不透明，不依赖上层容器
    canvas.drawRect(rect, Paint()..color = surface);

    if (!drawBlobs || strength <= 0 || palette.isEmpty) return;

    final double shortSide = size.shortestSide;

    for (final List<double> blob in AmbientBackground._blobs) {
      final Offset center = Offset(
        size.width * blob[0],
        size.height * blob[1],
      );
      final double radius = shortSide * blob[2];
      final int alpha =
          (blob[3] * strength * 255).round().clamp(0, 255).toInt();
      if (alpha <= 0) continue;

      final Color color = palette[blob[4].toInt() % palette.length];

      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            radius,
            <Color>[color.withAlpha(alpha), color.withAlpha(0)],
            <double>[0.0, 1.0],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter old) =>
      old.surface != surface ||
      old.strength != strength ||
      old.drawBlobs != drawBlobs ||
      !_samePalette(old.palette, palette);

  static bool _samePalette(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
