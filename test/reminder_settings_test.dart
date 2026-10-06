import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/settings/reminder_settings.dart';

/// 到点提醒设置的单测 —— M4 设置页补齐。
/// 重点：**关掉提醒 ≠ 不提醒**，只是不响不震；以及"总开关关了不该还在震"。
void main() {
  group('语义：关掉响铃 ≠ 不提醒', () {
    test('默认是响铃 + 震动', () {
      const ReminderSettings s = ReminderSettings();
      expect(s.soundEnabled, isTrue);
      expect(s.vibrateEnabled, isTrue);
      expect(s.effectiveVibrate, isTrue);
      expect(s.silent, isFalse);
    });

    test('★ 总开关关掉 → 静默，且震动被强制关掉（不会出现"关了还在震"）', () {
      const ReminderSettings s = ReminderSettings(
        soundEnabled: false,
        vibrateEnabled: true, // 用户之前开着震动
      );

      expect(s.silent, isTrue, reason: '走静默渠道，但通知照常出');
      expect(s.effectiveVibrate, isFalse, reason: '总开关关了就必须不震');
    });

    test('响铃开、震动关 → 只响不震', () {
      const ReminderSettings s = ReminderSettings(
        soundEnabled: true,
        vibrateEnabled: false,
      );

      expect(s.silent, isFalse);
      expect(s.effectiveVibrate, isFalse);
    });
  });

  group('持久化序列化', () {
    test('round-trip 无损', () {
      const ReminderSettings s = ReminderSettings(
        soundEnabled: false,
        vibrateEnabled: false,
      );
      expect(ReminderSettings.fromJson(s.toJson()), s);
    });

    test('★ 缺字段 / 类型不对 → 回退默认（默认是都开）', () {
      final ReminderSettings a = ReminderSettings.fromJson(<String, Object?>{});
      expect(a.soundEnabled, isTrue);
      expect(a.vibrateEnabled, isTrue);

      final ReminderSettings b = ReminderSettings.fromJson(<String, Object?>{
        'soundEnabled': 'yes',
        'vibrateEnabled': 1,
      });
      expect(b.soundEnabled, isTrue);
      expect(b.vibrateEnabled, isTrue);
    });

    test('copyWith 只改指定字段', () {
      const ReminderSettings s = ReminderSettings();
      expect(s.copyWith(soundEnabled: false).vibrateEnabled, isTrue);
      expect(s.copyWith(vibrateEnabled: false).soundEnabled, isTrue);
    });

    test('相等性（Notifier 用它判断"用户是否已改过"）', () {
      expect(const ReminderSettings(), const ReminderSettings());
      expect(
        const ReminderSettings(soundEnabled: false),
        isNot(const ReminderSettings()),
      );
    });
  });
}
