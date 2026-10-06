import 'package:flutter/material.dart';

import 'app_page_transitions.dart';
import 'design_tokens.dart';

/// 主题装配 —— 对应方案文档 5.2 节「设计令牌 / 颜色」
///
/// 颜色全部走 ColorScheme，禁止在页面里硬编码颜色值，
/// 否则深色模式和动态取色都会失效。
class AppTheme {
  const AppTheme._();

  /// 回退主色：番茄红。系统不支持动态取色时使用。
  static const Color seed = Color(0xFFE4572E);

  /// 从任意 ColorScheme 构建主题。
  /// scheme 来自：动态取色（优先）或 ColorScheme.fromSeed（回退）。
  static ThemeData from(ColorScheme scheme) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: _buildTextTheme(base.textTheme),
      // 所有二级页面的转场统一走这里（见 AppPageTransitionsBuilder）。
      // 必须注册在主题上而不是逐个 push 去写 —— 底下那一页的"让位"动画
      // 由它自己的路由驱动，而 AppShell 的路由是 MaterialApp.home 建的，
      // 只有主题能覆盖到它。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: AppPageTransitionsBuilder(),
          TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
          TargetPlatform.linux: AppPageTransitionsBuilder(),
          TargetPlatform.macOS: AppPageTransitionsBuilder(),
          TargetPlatform.windows: AppPageTransitionsBuilder(),
        },
      ),
      dividerTheme: DividerThemeData(
        color: scheme.onSurface.withValues(alpha: 0.08),
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(kPrimaryButtonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface.withValues(alpha: 0.55),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: scheme.onSurface.withValues(alpha: 0.75)),
      ),
    );
  }

  /// 字阶 —— 对应方案文档 5.2 节「字阶」表
  static TextTheme _buildTextTheme(TextTheme base) {
    return base.copyWith(
      // Display：主页剩余时间
      displayLarge: base.displayLarge?.copyWith(
        fontSize: 72,
        fontWeight: FontWeight.w200,
        letterSpacing: -2,
        height: 1.1,
      ),
      // Title：页面标题
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      // Subtitle：卡片标题
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w500,
      ),
      // Body：正文
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 15, height: 1.5),
      // Caption：辅助说明
      bodySmall: base.bodySmall?.copyWith(fontSize: 13, height: 1.4),
    );
  }
}
