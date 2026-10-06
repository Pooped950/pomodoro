import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';
import '../../domain/settings/app_theme_mode.dart';
import '../../domain/settings/background_settings.dart';
import '../../domain/settings/motion_settings.dart';
import '../../domain/settings/reminder_settings.dart';

/// 领域枚举 → Flutter 的 ThemeMode。
/// 映射放在表现层，让 `AppThemeMode` 保持不依赖 Flutter。
extension AppThemeModeX on AppThemeMode {
  ThemeMode get themeMode => switch (this) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };
}

/// 主题模式：启动读库、改动落库（与 TimerConfig 同一套 settings 表）。
class AppThemeModeNotifier extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() {
    unawaited(_restore());
    return AppThemeMode.system;
  }

  Future<void> _restore() async {
    try {
      final String? saved = await ref
          .read(settingsRepositoryProvider)
          .readString(SettingsRepository.keyThemeMode);
      if (saved == null) return;
      // 用户在读取完成前已经点过了 → 别用库里的旧值覆盖
      if (state != AppThemeMode.system) return;
      state = AppThemeMode.fromName(saved);
    } catch (_) {
      // 仓库未注入（测试环境）/ 读取失败 → 用默认值，不阻塞启动
    }
  }

  void set(AppThemeMode mode) {
    if (mode == state) return;
    state = mode;
    unawaited(_persist(mode));
  }

  Future<void> _persist(AppThemeMode mode) async {
    try {
      await ref.read(settingsRepositoryProvider).writeString(
            SettingsRepository.keyThemeMode,
            mode.name,
          );
    } on UnimplementedError {
      // provider 未注入（纯逻辑测试环境）
    } catch (_) {
      // 落盘失败不拖垮界面
    }
  }
}

final appThemeModeProvider =
    NotifierProvider<AppThemeModeNotifier, AppThemeMode>(
  AppThemeModeNotifier.new,
);

/// 到点提醒设置：启动读库、改动落库。
///
/// 注意：这两个开关**只影响响铃/震动**，不影响精确闹钟的排程 ——
/// 关掉提醒后到点依然会出通知，只是静默（见 [ReminderSettings] 的语义说明）。
class ReminderSettingsNotifier extends Notifier<ReminderSettings> {
  @override
  ReminderSettings build() {
    unawaited(_restore());
    return const ReminderSettings();
  }

  Future<void> _restore() async {
    try {
      final Map<String, Object?>? saved = await ref
          .read(settingsRepositoryProvider)
          .readJson(SettingsRepository.keyReminder);
      if (saved == null) return;
      // 用户在读取完成前已经点过了 → 别用库里的旧值覆盖
      if (state != const ReminderSettings()) return;
      state = ReminderSettings.fromJson(saved);
    } catch (_) {
      // 仓库未注入（测试环境）/ 读取失败 → 用默认值
    }
  }

  void setSoundEnabled(bool value) => _set(state.copyWith(soundEnabled: value));

  void setVibrateEnabled(bool value) =>
      _set(state.copyWith(vibrateEnabled: value));

  void _set(ReminderSettings next) {
    if (next == state) return;
    state = next;
    unawaited(_persist(next));
  }

  Future<void> _persist(ReminderSettings s) async {
    try {
      await ref.read(settingsRepositoryProvider).writeJson(
            SettingsRepository.keyReminder,
            s.toJson(),
          );
    } on UnimplementedError {
      // provider 未注入（纯逻辑测试环境）
    } catch (_) {
      // 落盘失败不拖垮界面
    }
  }
}

final reminderSettingsProvider =
    NotifierProvider<ReminderSettingsNotifier, ReminderSettings>(
  ReminderSettingsNotifier.new,
);

/// 动效节奏：启动读库、拖动滑动条时落库。
///
/// 这一个倍率作用到**全局所有动画**（见 `MotionTokens` / `Motion`）。
/// 之所以做成设置项而不是写死，是因为"多慢才叫丝滑"是主观的 ——
/// 与其猜一个值，不如把总闸交给用户，默认停在「从容」。
class MotionSettingsNotifier extends Notifier<MotionSettings> {
  @override
  MotionSettings build() {
    unawaited(_restore());
    return MotionSettings.defaults;
  }

  Future<void> _restore() async {
    try {
      final Map<String, Object?>? saved = await ref
          .read(settingsRepositoryProvider)
          .readJson(SettingsRepository.keyMotionScale);
      if (saved == null) return;
      // 用户在读取完成前已经拖过了 → 别用库里的旧值覆盖
      if (!state.isDefault) return;
      state = MotionSettings.fromJson(saved);
    } catch (_) {
      // 仓库未注入（测试环境）/ 读取失败 → 用默认档
    }
  }

  /// 改倍率。
  ///
  /// [persist] 为 false 时**只更新内存态、不落库** —— 拖动滑动条时
  /// `onChanged` 每帧都会回调，逐帧写库会拖慢拖动甚至卡顿。
  /// 所以拖动过程只更新界面，松手（`onChangeEnd`）才落库一次。
  void setScale(double scale, {bool persist = true}) {
    final MotionSettings next = MotionSettings(scale: scale);
    if (next != state) state = next;
    if (persist) unawaited(_persist(next));
  }

  Future<void> _persist(MotionSettings s) async {
    try {
      await ref.read(settingsRepositoryProvider).writeJson(
            SettingsRepository.keyMotionScale,
            s.toJson(),
          );
    } on UnimplementedError {
      // provider 未注入（纯逻辑测试环境）
    } catch (_) {
      // 落盘失败不拖垮界面
    }
  }
}

final motionSettingsProvider =
    NotifierProvider<MotionSettingsNotifier, MotionSettings>(
  MotionSettingsNotifier.new,
);

/// 主页背景：启动读库、改动落库。
///
/// ## 为什么"选图"不在这里做
///
/// 选图要弹系统相册、要复制文件到应用私有目录、还要删掉旧图 ——
/// 那是一串有副作用的异步操作，属于**页面**的职责（见设置页的背景分组）。
/// 这里只负责"当前背景是什么"这一个状态，保持 provider 干净、可单测。
class BackgroundSettingsNotifier extends Notifier<BackgroundSettings> {
  @override
  BackgroundSettings build() {
    unawaited(_restore());
    return const BackgroundSettings();
  }

  Future<void> _restore() async {
    try {
      final Map<String, Object?>? saved = await ref
          .read(settingsRepositoryProvider)
          .readJson(SettingsRepository.keyBackground);
      if (saved == null) return;
      // 用户在读取完成前已经改过了 → 别用库里的旧值覆盖
      if (state != const BackgroundSettings()) return;
      state = BackgroundSettings.fromJson(saved);
    } catch (_) {
      // 仓库未注入（测试环境）/ 读取失败 → 用默认背景
    }
  }

  void set(BackgroundSettings next) {
    if (next == state) return;
    state = next;
    unawaited(_persist(next));
  }

  /// 改暗度 / 模糊这类"不用重新选图"的字段。
  ///
  /// 单独给一个入口，是因为这两种改动**每拖一下都会触发**：
  /// 拖动时用 `persist: false` 只更新界面，松手再落库（同动效滑动条的做法）。
  void update(
    BackgroundSettings Function(BackgroundSettings current) transform, {
    bool persist = true,
  }) {
    final BackgroundSettings next = transform(state);
    if (next == state && persist) return;
    if (next != state) state = next;
    if (persist) unawaited(_persist(next));
  }

  Future<void> _persist(BackgroundSettings s) async {
    try {
      await ref.read(settingsRepositoryProvider).writeJson(
            SettingsRepository.keyBackground,
            s.toJson(),
          );
    } on UnimplementedError {
      // provider 未注入（纯逻辑测试环境）
    } catch (_) {
      // 落盘失败不拖垮界面
    }
  }
}

final backgroundSettingsProvider =
    NotifierProvider<BackgroundSettingsNotifier, BackgroundSettings>(
  BackgroundSettingsNotifier.new,
);
