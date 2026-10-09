import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/settings/class_reminder_settings.dart';
import '../../domain/timetable/class_reminder.dart';

/// 上课提醒的通道封装 —— `MethodChannel("pomodoro/classReminder")`。
///
/// 和 `ForegroundService` 同一套路：Dart 只负责**算规则**（[buildClassReminders]），
/// 排精确闹钟 / 到点发通知 / 响完排下一次，全在原生侧
/// （`ClassReminderScheduler` + `ClassAlarmReceiver`）——
/// 这样 **App 进程被系统回收后照样提醒**。
///
/// 所有方法都**不抛异常**：拿不到原生实现（宿主机测试 / 其他平台）时
/// 返回安全默认值，绝不让"排不上提醒"拖垮导入流程。
class ClassReminderService {
  const ClassReminderService();

  static const MethodChannel _channel =
      MethodChannel('pomodoro/classReminder');

  /// 把整份提醒规则 + 提醒方式交给原生排程。返回原生实际存下的条数。
  Future<int> apply(
    List<ClassReminder> reminders, {
    required ClassReminderSettings mode,
  }) async {
    final String json = jsonEncode(<Map<String, Object?>>[
      for (final ClassReminder r in reminders)
        <String, Object?>{
          'weekday': r.weekday,
          'minuteOfDay': r.minuteOfDay,
          'title': r.title,
          'body': r.body,
        },
    ]);
    try {
      final int? n = await _channel.invokeMethod<int>(
        'apply',
        <String, Object?>{
          'items': json,
          // 震动 / 响铃 / 两者 —— 原生按这个挑预建的通知渠道
          'vibrate': mode.vibrate,
          'sound': mode.sound,
        },
      );
      return n ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 清掉所有上课提醒（用户关了开关 / 清空课表）
  Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } catch (_) {
      // 拿不到原生实现就当作已经清干净
    }
  }

  /// 原生当前排了多少条（诊断 / 验收用）
  Future<int> count() async {
    try {
      return await _channel.invokeMethod<int>('count') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 能不能排**精确**闹钟。false 时原生会降级成不精确（可能晚几分钟）。
  Future<bool> canScheduleExact() async {
    try {
      return await _channel.invokeMethod<bool>('canScheduleExact') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 跳到系统「闹钟与提醒」授权页（Android 12 需要）
  Future<bool> openExactAlarmSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openExactAlarmSettings') ??
          false;
    } catch (_) {
      return false;
    }
  }
}
