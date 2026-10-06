import 'package:flutter/animation.dart';

/// 动效令牌 —— 全 App 的动画时长与曲线都从这里取，**页面里不要写魔法数字**。
///
/// ## 为什么需要这一层
///
/// 用户对动效的要求是「不要求快，要求丝滑补帧、高级」。这意味着两件事：
///   1. **时长要够长**，长到能看清过程（现在很多动画 200~300ms，一闪而过）
///   2. **曲线要"快起慢收"**，收尾拖得长才显得顺，而不是匀速滑完戛然而止
///
/// 所以这里把「时长」和「曲线」都集中定义，任何动画都引用它。
/// 想整体调快调慢时，**只改这一处 + [MotionSettings.scale] 这一个倍率**。
///
/// ## 这里的时长是「从容」档（倍率 1.0）的基准值
///
/// 实际生效时长 = 基准 × 用户设置的倍率（见 `MotionSettings.scale`）。
/// 用户在「设置 → 动效」里拖滑动条即可整体调快调慢。
///
/// ## 为什么不干脆把时长写得更长
///
/// 因为"慢"和"卡"只有一线之隔：
///   - 时长长但曲线收尾柔和 → 高级
///   - 时长长但曲线线性/生硬 → 迟钝
/// 所以这里时长只取到"能看清过程"的程度，剩下的"顺"全靠曲线。
class MotionTokens {
  const MotionTokens._();

  // ------------------------------------------------------------------
  // 时长（基准值，「从容」档）
  // ------------------------------------------------------------------

  /// 页面进入（push 一个二级页）。要够长才看得清"从哪来、到哪去"。
  static const Duration pageEnter = Duration(milliseconds: 420);

  /// 页面退出（pop）。**刻意比进入快** —— 返回是用户已经确认过的动作，
  /// 等太久会显得拖沓。进入慢、退出快是通用做法。
  static const Duration pageExit = Duration(milliseconds: 300);

  /// 底部弹层滑出（任务菜单、任务选择器）
  static const Duration sheetEnter = Duration(milliseconds: 380);

  /// 底部弹层收回
  static const Duration sheetExit = Duration(milliseconds: 260);

  /// 对话框进出
  static const Duration dialog = Duration(milliseconds: 300);

  /// 按压反馈（按下缩放 / 高光增强）。这个必须**短** ——
  /// 它是对手指的直接响应，长了会觉得"点不动"。
  static const Duration press = Duration(milliseconds: 140);

  /// 底部导航切页（点导航条滑到另一页）。
  ///
  /// 刻意比 [pageEnter] 短一点：切页是高频操作，用户会连续点几下，
  /// 每次都等 420ms 会觉得"点了没反应"。但也不能太快 ——
  /// 太快就看不到页面"滑过去"的过程，又变回生硬的瞬切了。
  static const Duration navSwitch = Duration(milliseconds: 360);

  /// 通用淡入淡出 / 尺寸变化 / 颜色变化
  static const Duration standard = Duration(milliseconds: 280);

  /// 列表逐项入场的**间隔**。第 n 项延迟 = n × 这个值。
  /// 45ms 是"能看出先后顺序、又不会等太久"的量级。
  static const Duration stagger = Duration(milliseconds: 45);

  /// 单次 stagger 延迟的上限 —— 列表很长时不能让最后一项等两秒。
  static const int maxStaggerSteps = 6;

  // ------------------------------------------------------------------
  // 曲线
  // ------------------------------------------------------------------

  /// 强调减速（进场主力曲线）：**极快起步、极长收尾**。
  ///
  /// 这是"高级感"的核心。Cubic(0.2, 0, 0, 1) 前 20% 时间走完 ~50% 路程，
  /// 剩下 80% 时间都在慢慢收尾 —— 视觉上就是"轻盈地滑进去然后稳稳停住"，
  /// 而不是"匀速平移过去"。
  static const Curve emphasized = Cubic(0.20, 0.00, 0.00, 1.00);

  /// 强调加速（退场主力曲线）：慢起快走，用于"滑走 / 消失"。
  static const Curve emphasizedIn = Cubic(0.30, 0.00, 0.80, 0.15);

  /// 标准曲线（Material 3 推荐），用于对称的小过渡。
  static const Curve standardCurve = Cubic(0.20, 0.00, 0.00, 1.00);

  /// 轻微回弹：末段略微冲过头再回落。
  ///
  /// 只用在**弹层出场**这种"有实体感"的地方（像一块板子被甩上来）。
  /// 不要用在页面转场上 —— 页面回弹会晕。
  static const Curve overshoot = Cubic(0.22, 1.20, 0.36, 1.00);

  /// 柔和进出（用于透明度/尺寸的往返）
  static const Curve soft = Curves.easeInOutCubic;

  /// 缓出（用于数字、进度这类"追上去"的变化）
  static const Curve gentleOut = Curves.easeOutCubic;
}
