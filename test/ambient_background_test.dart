import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/settings/background_settings.dart';
import 'package:pomodoro/presentation/widgets/ambient_background.dart';
import 'package:pomodoro/presentation/widgets/background_presets.dart';

/// 背景层的组件测试。
///
/// 为什么要测"能不能画出来"而不是只测数据模型：
/// 背景是主页最底层的一整块，**它一旦抛异常，用户看到的就是一整片空白**，
/// 会直接认为"App 坏了"。而背景的三种形态（主题 / 预设 / 相册照片）
/// 里，照片那种最容易出问题 —— 文件可能被清理、可能根本不是图片。
/// 所以这里把每种形态都真的渲染一遍，确认不抛异常、且有兜底。
void main() {
  Future<void> pumpBackground(
    WidgetTester tester,
    BackgroundSettings settings,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AmbientBackground(
              // 传 settings 而不是依赖全局 provider：
              // 这样测试不需要注入数据库仓储（provider 未注入会抛错）
              settings: settings,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    // 图片解码 / 淡入是异步的，多推几帧让它走到稳定态
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('三种背景形态都能渲染，不抛异常', () {
    testWidgets('主题背景（默认）', (WidgetTester tester) async {
      await pumpBackground(tester, const BackgroundSettings());
      expect(find.byType(AmbientBackground), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('★ 每一个预设色卡都渲染一遍', (WidgetTester tester) async {
      expect(kBackgroundPresets, isNotEmpty);

      for (final BackgroundPreset p in kBackgroundPresets) {
        // 预设本身的基本约束：有名字、有足够画光斑的颜色
        expect(p.name, isNotEmpty, reason: '预设 ${p.id} 没有名字');
        expect(
          p.colors.length,
          greaterThanOrEqualTo(2),
          reason: '预设 ${p.id} 颜色不够画光斑',
        );
        expect(p.strengthScale, greaterThan(0));

        await pumpBackground(
          tester,
          BackgroundSettings(kind: BackgroundKind.preset, presetId: p.id),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '预设 ${p.id} 渲染时抛异常了',
        );
      }
    });

    testWidgets('★ 未知 presetId 回退到第一个预设，不崩', (WidgetTester tester) async {
      await pumpBackground(
        tester,
        const BackgroundSettings(
          kind: BackgroundKind.preset,
          presetId: '这个预设不存在',
        ),
      );
      expect(tester.takeException(), isNull);
      expect(presetById('这个预设不存在').id, kBackgroundPresets.first.id);
    });

    testWidgets('★ 照片文件不存在 → 回退主题背景，不崩（绝不能是白板）',
        (WidgetTester tester) async {
      await pumpBackground(
        tester,
        const BackgroundSettings(
          kind: BackgroundKind.image,
          imagePath: '/definitely/not/here.jpg',
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('照片模式：模糊开 / 关都能渲染', (WidgetTester tester) async {
      for (final bool blurred in <bool>[true, false]) {
        await pumpBackground(
          tester,
          BackgroundSettings(
            kind: BackgroundKind.image,
            imagePath: '/nope.jpg',
            blurred: blurred,
          ),
        );
        expect(tester.takeException(), isNull, reason: 'blurred=$blurred 失败');
      }
    });

    testWidgets('暗度取到两个极值都能渲染', (WidgetTester tester) async {
      for (final double dim in <double>[
        BackgroundSettings.minDim,
        BackgroundSettings.maxDim,
      ]) {
        await pumpBackground(
          tester,
          BackgroundSettings(
            kind: BackgroundKind.preset,
            presetId: 'ocean',
            dim: dim,
          ),
        );
        expect(tester.takeException(), isNull, reason: 'dim=$dim 失败');
      }
    });
  });

  group('环境色强度', () {
    test('★ 预设色卡必须明显强于主题背景（否则用户选了看不出变化）', () {
      final double theme = resolveAmbientStrength(
        isDark: false,
        preset: null,
        override: null,
      );
      final double preset = resolveAmbientStrength(
        isDark: false,
        preset: kBackgroundPresets.first,
        override: null,
      );

      expect(
        preset,
        greaterThan(theme * 1.5),
        reason: '2026-10-06 实测踩到：不加成时预设和主题的整图平均色只差 2/255，'
            '肉眼看不出，等于自定义背景没生效',
      );
    });

    test('深色主题下也成立', () {
      final double theme = resolveAmbientStrength(
        isDark: true,
        preset: null,
        override: null,
      );
      final double preset = resolveAmbientStrength(
        isDark: true,
        preset: kBackgroundPresets.first,
        override: null,
      );
      expect(preset, greaterThan(theme * 1.5));
    });

    test('override 优先于一切（预览 / 调试用）', () {
      expect(
        resolveAmbientStrength(
          isDark: false,
          preset: kBackgroundPresets.first,
          override: 0.11,
        ),
        0.11,
      );
      expect(
        resolveAmbientStrength(isDark: true, preset: null, override: 0.9),
        0.9,
      );
    });

    test('强度是正数、且没有大到把内容淹掉（上限 1.0）', () {
      for (final BackgroundPreset p in kBackgroundPresets) {
        for (final bool dark in <bool>[true, false]) {
          final double s =
              resolveAmbientStrength(isDark: dark, preset: p, override: null);
          expect(s, greaterThan(0));
          expect(
            s,
            lessThanOrEqualTo(1.0),
            reason: '预设 ${p.id} 在 dark=$dark 下强度 $s 过大，会把界面内容淹掉',
          );
        }
      }
    });

    test('每个预设的 strengthScale 都合理', () {
      for (final BackgroundPreset p in kBackgroundPresets) {
        expect(p.strengthScale, greaterThan(0.5));
        expect(p.strengthScale, lessThanOrEqualTo(1.0));
      }
    });
  });

  group('色卡取样', () {
    test('每个预设都能取到两个颜色画小圆点（颜色不够时用第一个补）', () {
      for (final BackgroundPreset p in kBackgroundPresets) {
        final List<Color> swatch = presetSwatchColors(p);
        expect(swatch.length, 2);
        expect(swatch[0], isA<Color>());
        expect(swatch[1], isA<Color>());
      }
    });

    test('预设 id 不重复（重复的话选中态会同时亮两个）', () {
      final Set<String> ids = <String>{};
      for (final BackgroundPreset p in kBackgroundPresets) {
        expect(ids.add(p.id), isTrue, reason: '预设 id 重复：${p.id}');
      }
    });

    test('预设名字不重复', () {
      final Set<String> names = <String>{};
      for (final BackgroundPreset p in kBackgroundPresets) {
        expect(names.add(p.name), isTrue, reason: '预设名字重复：${p.name}');
      }
    });
  });
}
