# 一颗番茄 🍅

一款 Android 番茄钟 App：计时、任务与统计、课表导入，界面走柔光玻璃风格。

## 特性

- **可靠的计时**：基于绝对时间戳的计时引擎（进程被杀、手机重启都不会算错）；前台服务 + 常驻通知栏倒计时 + 精确闹钟兜底，息屏后台到点照样提醒
- **后台保活引导**：针对国产 ROM（澎湃OS / MIUI 等）的后台限制，提供通知 / 精确闹钟 / 电池优化 / 自启动四项状态检查与一键跳转
- **任务与统计**：专注可绑定任务；今日概览、近 7 天柱状图、任务分布
- **课表导入**：内置 OCR（ML Kit 模型随包），选一张课表截图即可识别；支持粘贴作息表把每节课时间排到分钟
- **液态玻璃视觉**：柔光玻璃材质、动态取色（跟随系统壁纸）、可自定义背景（预设色卡 / 相册照片）、全局动效节奏可调

## 系统要求

- Android 8.0+（在 Android 17 / 澎湃OS 上开发验证）

## 构建

```bash
flutter pub get
flutter test
flutter build apk --release
```

- Flutter 3.47+ / JDK 17 / Android SDK（compileSdk 36）
- 产物位于 `build/app/outputs/flutter-apk/app-release.apk`

## 项目结构

```
lib/
├── core/            # 主题、设计令牌、动效规范、页面转场
├── domain/          # 领域模型与纯函数（计时协议 / 任务 / 统计 / 设置 / OCR）
├── data/            # SQLite 仓储层（sessions / tasks / settings）+ 服务封装
├── presentation/    # 页面、组件、Riverpod 状态
android/app/src/main/kotlin/com/pooped950/pomodoro/
└── *.kt             # 前台服务、精确闹钟接收器、保活通道（Kotlin 原生）
test/                # 313 个单元测试（纯函数层全覆盖）
```

设计要点：领域层不依赖 Flutter（可直接单测）；计时状态由原生前台服务自持，
通知栏动作与 Dart 侧双向同步；App 进程被回收后由 `AlarmManager` 精确闹钟兜底提醒。

## 许可证

[MIT](LICENSE) © 2026 Pooped950 ([@Pooped950](https://github.com/Pooped950))
