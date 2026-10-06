import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/theme/motion_tokens.dart';
import 'package:pomodoro/domain/settings/motion_settings.dart';

/// 动效节奏设置的单测。
///
/// 这里守的是两条底线：
///   1. **倍率永远不会变成 0 或负数** —— 那会让所有动画瞬间完成，
///      用户看到的是"动效全坏了"，而且完全联想不到是设置项的问题
///   2. **脏数据（缺字段 / 字符串 / null）回退默认档，不抛异常**
void main() {
  group('MotionSettings 默认值与夹取', () {
    test('默认是「从容」档（用户要求默认停在这一档）', () {
      expect(MotionSettings.defaults.scale, MotionSettings.defaultScale);
      expect(MotionSettings.defaults.label, '从容');
      expect(MotionSettings.defaults.isDefault, isTrue);
      expect(MotionSettings().scale, MotionSettings.defaultScale);
    });

    test('★ 倍率被夹在 [minScale, maxScale] 内（构造时就夹好，实例永远合法）', () {
      expect(MotionSettings(scale: 0).scale, MotionSettings.minScale);
      expect(MotionSettings(scale: -5).scale, MotionSettings.minScale);
      expect(MotionSettings(scale: 99).scale, MotionSettings.maxScale);
      expect(MotionSettings(scale: double.nan).scale,
          MotionSettings.defaultScale);
    });

    test('★ 无论传什么，倍率永远 > 0（否则动画瞬间完成，等于动效全没了）', () {
      for (final double raw in <double>[-1, 0, 0.0001, double.nan, 1e9]) {
        expect(MotionSettings(scale: raw).scale, greaterThan(0));
      }
    });

    test('区间内的值原样保留，不被改动', () {
      expect(MotionSettings(scale: 1.25).scale, 1.25);
      expect(MotionSettings(scale: MotionSettings.minScale).scale,
          MotionSettings.minScale);
      expect(MotionSettings(scale: MotionSettings.maxScale).scale,
          MotionSettings.maxScale);
    });

    test('copyWith 同样会夹取', () {
      expect(
        MotionSettings.defaults.copyWith(scale: -1).scale,
        MotionSettings.minScale,
      );
    });
  });

  group('档位名随倍率推进', () {
    test('从最小拖到最大，档位名依次是 轻盈→从容→舒缓→悠长', () {
      expect(MotionSettings(scale: MotionSettings.minScale).label, '轻盈');
      expect(MotionSettings(scale: 1.0).label, '从容');
      expect(MotionSettings(scale: 1.2).label, '舒缓');
      expect(MotionSettings(scale: MotionSettings.maxScale).label, '悠长');
    });

    test('每个档位都有非空的解释文案（界面要显示，不能是空串）', () {
      for (final double scale in <double>[0.65, 1.0, 1.2, 1.5]) {
        final MotionSettings s = MotionSettings(scale: scale);
        expect(s.label, isNotEmpty);
        expect(s.hint, isNotEmpty);
      }
    });
  });

  group('时长换算', () {
    test('倍率 1.0 → 原样返回基准时长', () {
      expect(
        MotionSettings.defaults.of(MotionTokens.pageEnter),
        MotionTokens.pageEnter,
      );
    });

    test('倍率越大时长越长（单调）', () {
      const Duration base = Duration(milliseconds: 400);
      final int slow = MotionSettings(scale: 1.5).of(base).inMilliseconds;
      final int mid = MotionSettings(scale: 1.0).of(base).inMilliseconds;
      final int fast = MotionSettings(scale: 0.65).of(base).inMilliseconds;

      expect(slow, 600);
      expect(mid, 400);
      expect(fast, lessThan(mid));
      expect(fast, greaterThan(0));
    });

    test('所有基准时长都是正数（写错成 0 会让动画瞬间完成）', () {
      const List<Duration> all = <Duration>[
        MotionTokens.pageEnter,
        MotionTokens.pageExit,
        MotionTokens.sheetEnter,
        MotionTokens.sheetExit,
        MotionTokens.dialog,
        MotionTokens.press,
        MotionTokens.standard,
        MotionTokens.stagger,
      ];
      for (final Duration d in all) {
        expect(d.inMilliseconds, greaterThan(0));
      }
    });

    test('★ 进场比退场慢（进入要看清过程，返回要干脆）', () {
      expect(
        MotionTokens.pageEnter.inMilliseconds,
        greaterThan(MotionTokens.pageExit.inMilliseconds),
      );
      expect(
        MotionTokens.sheetEnter.inMilliseconds,
        greaterThan(MotionTokens.sheetExit.inMilliseconds),
      );
    });

    test('★ 按压反馈明显短于页面转场（手指按下要立刻有反应）', () {
      expect(
        MotionTokens.press.inMilliseconds,
        lessThan(MotionTokens.pageEnter.inMilliseconds / 2),
      );
    });
  });

  group('序列化容错', () {
    test('round-trip 无损', () {
      final MotionSettings s = MotionSettings(scale: 1.3);
      expect(MotionSettings.fromJson(s.toJson()), s);
    });

    test('★ 缺字段 / 类型不对 / null 一律回退默认档，不抛异常', () {
      expect(MotionSettings.fromJson(null), MotionSettings.defaults);
      expect(MotionSettings.fromJson(<String, Object?>{}),
          MotionSettings.defaults);
      expect(MotionSettings.fromJson(<String, Object?>{'scale': 'fast'}),
          MotionSettings.defaults);
      expect(MotionSettings.fromJson(<String, Object?>{'scale': null}),
          MotionSettings.defaults);
    });

    test('★ JSON 里的整数（1 而不是 1.0）也能读，不强转 double 抛异常', () {
      expect(
        MotionSettings.fromJson(<String, Object?>{'scale': 1}).scale,
        1.0,
      );
    });

    test('★ 库里存了越界值也能夹回来（手工改过库 / 老版本数据）', () {
      expect(
        MotionSettings.fromJson(<String, Object?>{'scale': 100}).scale,
        MotionSettings.maxScale,
      );
      expect(
        MotionSettings.fromJson(<String, Object?>{'scale': -3}).scale,
        MotionSettings.minScale,
      );
    });
  });
}
