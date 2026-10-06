import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/timer/timer_engine.dart';

/// TimerConfig 持久化序列化的单测（M4）。
/// 重点是"缺字段不能读成 0" —— 那会让专注时长变成 0 分钟。
void main() {
  group('toJson → fromJson round-trip', () {
    test('全部字段无损往返', () {
      const TimerConfig c = TimerConfig(
        focusMinutes: 45,
        shortBreakMinutes: 8,
        longBreakMinutes: 20,
        longBreakInterval: 3,
        autoStartNext: true,
      );

      final TimerConfig back = TimerConfig.fromJson(c.toJson());

      expect(back, c);
      expect(back.focusMinutes, 45);
      expect(back.shortBreakMinutes, 8);
      expect(back.longBreakMinutes, 20);
      expect(back.longBreakInterval, 3);
      expect(back.autoStartNext, isTrue);
    });

    test('默认值往返后仍是默认值', () {
      const TimerConfig c = TimerConfig();
      expect(TimerConfig.fromJson(c.toJson()), c);
    });
  });

  group('fromJson 容错', () {
    test('★ 空 JSON → 全部回退默认值（不是 0）', () {
      final TimerConfig c = TimerConfig.fromJson(<String, Object?>{});

      expect(c.focusMinutes, 25, reason: '读成 0 会让专注时长变 0 分钟');
      expect(c.shortBreakMinutes, 5);
      expect(c.longBreakMinutes, 15);
      expect(c.longBreakInterval, 4);
      expect(c.autoStartNext, isFalse);
    });

    test('★ 只存了部分字段（老版本 JSON）→ 缺的用默认值，有的保留', () {
      final TimerConfig c = TimerConfig.fromJson(<String, Object?>{
        'focusMinutes': 30,
      });

      expect(c.focusMinutes, 30);
      expect(c.shortBreakMinutes, 5, reason: '缺失字段回退默认');
      expect(c.longBreakInterval, 4);
    });

    test('数值存成 double（JSON 反序列化常见）也能读', () {
      final TimerConfig c = TimerConfig.fromJson(<String, Object?>{
        'focusMinutes': 30.0,
        'longBreakInterval': 2.0,
      });

      expect(c.focusMinutes, 30);
      expect(c.longBreakInterval, 2);
    });

    test('字段类型完全不对 → 回退默认，不抛异常', () {
      final TimerConfig c = TimerConfig.fromJson(<String, Object?>{
        'focusMinutes': 'abc',
        'autoStartNext': 1,
      });

      expect(c.focusMinutes, 25);
      expect(c.autoStartNext, isFalse);
    });
  });

  group('相等性（TimerConfigNotifier 用它判断"用户是否已改过"）', () {
    test('同值相等、异值不等', () {
      expect(const TimerConfig(), const TimerConfig());
      expect(const TimerConfig().hashCode, const TimerConfig().hashCode);
      expect(const TimerConfig(focusMinutes: 30), isNot(const TimerConfig()));
      expect(
        const TimerConfig(autoStartNext: true),
        isNot(const TimerConfig()),
      );
    });
  });
}
