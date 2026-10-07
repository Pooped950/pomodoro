import 'package:flutter/material.dart';

/// 课程格子的一对颜色：底色 + 压在上面的文字色。
@immutable
class CourseColor {
  const CourseColor({required this.fill, required this.onFill});

  /// 格子底色
  final Color fill;

  /// 格子上的文字色 —— 和 [fill] 保证对比度，不要自己另配
  final Color onFill;
}

/// 课表配色板的大小。
///
/// 10 是权衡：够多，一般人的课表不会撞色；又够少，色相转一圈不会回到起点附近。
const int kTimetablePaletteSize = 10;

/// 按课程配色序号取一对颜色。
///
/// ## 为什么不写死一张色表（硬约束：页面禁止硬编码颜色）
///
/// 这个 App 的颜色全部来自 `Theme.of(context).colorScheme`（含动态取色），
/// 写死一张 RGB 表就等于在主题体系之外另开一套，换主题 / 跟随壁纸时
/// 课表会变成唯一的"外来色"。
///
/// 做法：拿主题主色当**种子**，按黄金角（137.5°）在色相环上推开 ——
/// 黄金角能保证相邻色号的颜色差得足够开，也不会像均分那样转两圈就回到起点。
/// 明度 / 饱和度按当前是深色还是浅色主题分档，保证格子上的字读得清。
CourseColor courseColorFor(ColorScheme scheme, int index) {
  final HSLColor base = HSLColor.fromColor(scheme.primary);
  final int i = index % kTimetablePaletteSize;
  final double hue = (base.hue + i * 137.508) % 360;

  final bool dark = scheme.brightness == Brightness.dark;

  // 底色：浅色主题用高明度淡彩（像便签纸），深色主题用低明度深彩
  final Color fill = HSLColor.fromAHSL(
    1,
    hue,
    dark ? 0.34 : 0.52,
    dark ? 0.24 : 0.90,
  ).toColor();

  // 文字：同一色相往反方向拉到极端明度，天然和底色拉开对比
  final Color onFill = HSLColor.fromAHSL(
    1,
    hue,
    dark ? 0.55 : 0.72,
    dark ? 0.86 : 0.28,
  ).toColor();

  return CourseColor(fill: fill, onFill: onFill);
}
