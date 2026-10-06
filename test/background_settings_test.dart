import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/settings/background_settings.dart';

/// 背景设置的单测。
///
/// 这里守的核心是**"背景画不出来"这件事绝不能发生** ——
/// 背景是主页最底层的一整块，它一旦画不出来，用户看到的就是一块空白，
/// 会直接认为"App 坏了"。所以：
///   1. 选了图片但文件没了 → 必须回退到主题背景（[effectiveKind]）
///   2. 任何脏数据（类型不对 / 未知枚举 / 越界数值）都必须回退默认值
void main() {
  group('默认值', () {
    test('默认是跟随主题，不依赖任何外部资源', () {
      const BackgroundSettings s = BackgroundSettings();
      expect(s.kind, BackgroundKind.theme);
      expect(s.effectiveKind, BackgroundKind.theme);
      expect(s.hasUsableImage, isFalse);
      expect(s.blurred, isTrue, reason: '模糊是更好看的默认值');
    });

    test('默认预设 id 是合法非空串', () {
      expect(BackgroundSettings.defaultPresetId, isNotEmpty);
    });
  });

  group('effectiveKind 的回退', () {
    test('★ 选了图片但路径为 null → 回退主题背景（否则是一块白板）', () {
      const BackgroundSettings s =
          BackgroundSettings(kind: BackgroundKind.image);
      expect(s.hasUsableImage, isFalse);
      expect(s.effectiveKind, BackgroundKind.theme);
    });

    test('★ 选了图片但路径是空串 → 同样回退主题背景', () {
      const BackgroundSettings s = BackgroundSettings(
        kind: BackgroundKind.image,
        imagePath: '',
      );
      expect(s.hasUsableImage, isFalse);
      expect(s.effectiveKind, BackgroundKind.theme);
    });

    test('路径有效时才是图片背景', () {
      const BackgroundSettings s = BackgroundSettings(
        kind: BackgroundKind.image,
        imagePath: '/data/app/backgrounds/bg_1.jpg',
      );
      expect(s.hasUsableImage, isTrue);
      expect(s.effectiveKind, BackgroundKind.image);
    });

    test('预设 / 主题类型不受路径影响', () {
      const BackgroundSettings preset = BackgroundSettings(
        kind: BackgroundKind.preset,
        imagePath: null,
      );
      expect(preset.effectiveKind, BackgroundKind.preset);
    });
  });

  group('暗度夹取', () {
    test('★ 越界值被夹回区间（负暗度会让亮图完全压不住文字）', () {
      expect(BackgroundSettings.clampDim(-1), BackgroundSettings.minDim);
      expect(BackgroundSettings.clampDim(5), BackgroundSettings.maxDim);
      expect(BackgroundSettings.clampDim(double.nan),
          BackgroundSettings.defaultDim);
    });

    test('区间内的值原样保留', () {
      expect(BackgroundSettings.clampDim(0.42), 0.42);
      expect(BackgroundSettings.clampDim(BackgroundSettings.minDim),
          BackgroundSettings.minDim);
      expect(BackgroundSettings.clampDim(BackgroundSettings.maxDim),
          BackgroundSettings.maxDim);
    });
  });

  group('copyWith', () {
    test('clearImagePath 能把路径清掉', () {
      const BackgroundSettings s = BackgroundSettings(
        kind: BackgroundKind.image,
        imagePath: '/x/bg_1.jpg',
      );
      final BackgroundSettings cleared = s.copyWith(
        kind: BackgroundKind.theme,
        clearImagePath: true,
      );
      expect(cleared.imagePath, isNull);
      expect(cleared.effectiveKind, BackgroundKind.theme);
    });

    test('不传 clearImagePath 时路径保留（换预设不该丢掉已选的照片）', () {
      const BackgroundSettings s = BackgroundSettings(
        kind: BackgroundKind.image,
        imagePath: '/x/bg_1.jpg',
      );
      final BackgroundSettings switched =
          s.copyWith(kind: BackgroundKind.preset, presetId: 'ocean');
      expect(switched.imagePath, '/x/bg_1.jpg');
      expect(switched.presetId, 'ocean');
    });

    test('dim 也会被夹取', () {
      expect(
        const BackgroundSettings().copyWith(dim: 99).dim,
        BackgroundSettings.maxDim,
      );
    });
  });

  group('序列化容错', () {
    test('round-trip 无损', () {
      const BackgroundSettings s = BackgroundSettings(
        kind: BackgroundKind.image,
        presetId: 'dusk',
        imagePath: '/x/bg_9.jpg',
        dim: 0.5,
        blurred: false,
      );
      expect(BackgroundSettings.fromJson(s.toJson()), s);
    });

    test('★ null / 空 JSON → 默认值，不抛异常', () {
      expect(BackgroundSettings.fromJson(null), const BackgroundSettings());
      expect(BackgroundSettings.fromJson(<String, Object?>{}),
          const BackgroundSettings());
    });

    test('★ 未知 kind 名 → 回退主题背景（一定画得出来）', () {
      expect(
        BackgroundSettings.fromJson(<String, Object?>{'kind': 'video'}).kind,
        BackgroundKind.theme,
      );
      expect(
        BackgroundSettings.fromJson(<String, Object?>{'kind': 123}).kind,
        BackgroundKind.theme,
      );
    });

    test('★ 类型不对的字段各自回退，而不是整条记录作废', () {
      final BackgroundSettings s = BackgroundSettings.fromJson(
        <String, Object?>{
          'kind': 'preset',
          'presetId': 42, // 应该是字符串
          'imagePath': <String>['x'], // 应该是字符串
          'dim': 'dark', // 应该是数字
          'blurred': 'yes', // 应该是布尔
        },
      );

      expect(s.kind, BackgroundKind.preset, reason: '合法字段要保住');
      expect(s.presetId, BackgroundSettings.defaultPresetId);
      expect(s.imagePath, isNull);
      expect(s.dim, BackgroundSettings.defaultDim);
      expect(s.blurred, isTrue);
    });

    test('★ 越界的 dim 从库里读出来也会被夹回', () {
      expect(
        BackgroundSettings.fromJson(<String, Object?>{'dim': 9}).dim,
        BackgroundSettings.maxDim,
      );
    });

    test('★ JSON 里的整数 dim（0 而不是 0.0）也能读', () {
      expect(
        BackgroundSettings.fromJson(<String, Object?>{'dim': 0}).dim,
        0.0,
      );
    });

    test('空串 presetId / imagePath 视为未设置', () {
      final BackgroundSettings s = BackgroundSettings.fromJson(
        <String, Object?>{'presetId': '', 'imagePath': ''},
      );
      expect(s.presetId, BackgroundSettings.defaultPresetId);
      expect(s.imagePath, isNull);
    });
  });

  group('图片解码上限', () {
    test('★ 解码宽度有上限（相册原图整张解码要几十 MB，再叠模糊会卡住）', () {
      expect(BackgroundSettings.imageDecodeWidth, greaterThan(0));
      expect(BackgroundSettings.imageDecodeWidth, lessThanOrEqualTo(1600));
    });
  });
}
