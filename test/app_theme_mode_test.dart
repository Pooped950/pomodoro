import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/settings/app_theme_mode.dart';

/// 外观设置（主题模式）的单测 —— M4 设置页补齐。
/// 重点是"脏值不能让界面崩"：库里存的值可能被手工改过或来自老版本。
void main() {
  group('AppThemeMode.fromName', () {
    test('三个合法值都能还原', () {
      expect(AppThemeMode.fromName('system'), AppThemeMode.system);
      expect(AppThemeMode.fromName('light'), AppThemeMode.light);
      expect(AppThemeMode.fromName('dark'), AppThemeMode.dark);
    });

    test('★ 未知 / null / 空串 / 大小写不符 一律回退默认值（dark），不抛异常', () {
      expect(AppThemeMode.fromName(null), AppThemeMode.dark);
      expect(AppThemeMode.fromName(''), AppThemeMode.dark);
      expect(AppThemeMode.fromName('Dark'), AppThemeMode.dark);
      expect(AppThemeMode.fromName('{"a":1}'), AppThemeMode.dark);
    });

    test('name 与 label 都非空（name 用于落库，label 用于界面）', () {
      for (final AppThemeMode m in AppThemeMode.values) {
        expect(m.name, isNotEmpty);
        expect(m.label, isNotEmpty);
      }
    });

    test('落库用的 name 能原样还原（往返一致）', () {
      for (final AppThemeMode m in AppThemeMode.values) {
        expect(AppThemeMode.fromName(m.name), m);
      }
    });
  });
}
