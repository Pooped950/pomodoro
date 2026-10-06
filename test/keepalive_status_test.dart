import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/data/services/keepalive_service.dart';

/// 后台保活状态模型的单测（M3 阶段四）。
/// 重点是"未知"与"未开"不能混为一谈 —— 自启动查不到时不能算作未开。
void main() {
  group('KeepAliveStatus.unknown', () {
    test('拿不到原生状态时按"都还没开"处理，不谎报就绪', () {
      final KeepAliveStatus s = KeepAliveStatus.unknown();

      expect(s.notificationsEnabled, isFalse);
      expect(s.exactAlarmAllowed, isFalse);
      expect(s.batteryUnrestricted, isFalse);
      expect(s.autoStartAllowed, isNull, reason: '未知，不是 false');
      expect(s.allReady, isFalse);
      // 只数三项明确的，自启动未知不计入
      expect(s.pendingCount, 3);
    });
  });

  group('fromMap 解析', () {
    test('null / 缺 key → 安全默认（都按未开）', () {
      expect(KeepAliveStatus.fromMap(null).notificationsEnabled, isFalse);

      final KeepAliveStatus s = KeepAliveStatus.fromMap(<Object?, Object?>{
        'notificationsEnabled': true,
      });
      expect(s.notificationsEnabled, isTrue);
      expect(s.exactAlarmAllowed, isFalse);
      expect(s.batteryUnrestricted, isFalse);
      expect(s.autoStartAllowed, isNull);
    });

    test('四项全开 → allReady，pendingCount 为 0', () {
      final KeepAliveStatus s = KeepAliveStatus.fromMap(<Object?, Object?>{
        'notificationsEnabled': true,
        'exactAlarmAllowed': true,
        'batteryUnrestricted': true,
        'autoStartAllowed': true,
        'isMiuiLike': true,
      });

      expect(s.allReady, isTrue);
      expect(s.pendingCount, 0);
      expect(s.isMiuiLike, isTrue);
    });

    test('★ 自启动未知(null) 不计入 pendingCount，也不阻塞 allReady', () {
      final KeepAliveStatus s = KeepAliveStatus.fromMap(<Object?, Object?>{
        'notificationsEnabled': true,
        'exactAlarmAllowed': true,
        'batteryUnrestricted': true,
        'autoStartAllowed': null,
      });

      expect(s.autoStartAllowed, isNull);
      expect(s.pendingCount, 0, reason: '未知不能算作未开');
      expect(s.allReady, isTrue);
    });

    test('★ 自启动明确为 false 时要计入 pendingCount', () {
      final KeepAliveStatus s = KeepAliveStatus.fromMap(<Object?, Object?>{
        'notificationsEnabled': true,
        'exactAlarmAllowed': true,
        'batteryUnrestricted': true,
        'autoStartAllowed': false,
      });

      expect(s.pendingCount, 1);
      expect(s.allReady, isFalse);
    });

    test('部分未开 → pendingCount 精确计数', () {
      final KeepAliveStatus s = KeepAliveStatus.fromMap(<Object?, Object?>{
        'notificationsEnabled': false,
        'exactAlarmAllowed': true,
        'batteryUnrestricted': false,
        'autoStartAllowed': false,
      });

      expect(s.pendingCount, 3);
      expect(s.allReady, isFalse);
    });
  });
}
