import 'package:flutter/material.dart';

import '../../../core/app_info.dart';
import 'update_dialog.dart';

/// 使用手册的**内容版本** —— 只管"弹不弹"，**不是显示给用户的版本号**。
///
/// ## 这个数字是"弹不弹"的开关
///
/// 用户看过的手册版本存在 `settings` 里。每次启动比对：
///   - 存的和 [kManualVersion] **一样** → 不再弹
///   - 不一样（首次安装、或者手册内容改版了）→ 再弹一次
///
/// ⚠️ 2026-10-07 起**显示**的版本走 [kAppVersion]（手册弹窗右上角 + 最后一页标题）：
/// 大版本的"这次更新了什么"由启动时的大版本更新弹窗负责（见 `update_dialog.dart`），
/// 手册不必每次发版都跟着重弹一遍。所以这个号**只在手册结构 / 正文改版时才升**
/// （升了老用户会再看一次手册）。
/// 早先把这里当版本号显示，结果 2.x 的 App 里手册写着 `v1.9.0`。
const String kManualVersion = '1.9.0';

/// 手册里的一页
@immutable
class ManualPage {
  const ManualPage({
    required this.icon,
    required this.title,
    required this.body,
    this.bullets = const <String>[],
    this.tint,
  });

  final IconData icon;
  final String title;

  /// 正文。用 `**…**` 包住的部分会渲染成强调色。
  final String body;

  /// 要点列表
  final List<String> bullets;

  /// 这一页的主色调；null = 用主题主色
  final Color? tint;
}

/// 手册最后一页「更新内容」要列的东西。
///
/// 直接复用大版本更新弹窗那份文案（[kMajorUpdateNotes]）—— 两处说的是同一件事
/// （"这次更新你得到了什么"），抄成两份迟早会漂移。
const List<String> kReleaseNotes = kMajorUpdateNotes;

/// 手册的全部页面。顺序就是滑动的顺序。
final List<ManualPage> kManualPages = <ManualPage>[
  const ManualPage(
    icon: Icons.spa_outlined,
    title: '一颗番茄',
    body: '一个用「专注 / 休息」节奏工作的番茄钟。\n\n'
        '计时、任务、统计、课表四块放在一起，打开就能用。',
    bullets: <String>[
      '用「专注 / 休息」的节奏工作',
      '息屏、清后台，到点照样提醒',
      '课表、任务、统计放在一起，不用来回切',
    ],
  ),
  const ManualPage(
    icon: Icons.timer_outlined,
    title: '计时',
    body: '计时用的是**绝对时间戳**，不是"每秒减一"。\n\n'
        '所以不管 App 在后台、息屏，还是被系统冻结，时间都不会走偏。',
    bullets: <String>[
      '点主按钮开始 / 暂停 / 继续',
      '到点自动进入下一阶段（可以在设置里关掉）',
      '第 4 个番茄之后进入长休息',
    ],
  ),
  ManualPage(
    icon: Icons.check_circle_outline,
    title: '任务',
    body: '把每个番茄**绑定到一个任务**，就知道专注的时间花在哪了。',
    bullets: const <String>[
      '在「任务」页新建任务，填上预估番茄数',
      '开始专注前先选一个任务',
      '进度条会跟着完成的番茄数往前走',
    ],
    tint: const Color(0xFF3B6D11),
  ),
  ManualPage(
    icon: Icons.bar_chart_rounded,
    title: '统计',
    body: '看清楚自己的专注习惯。\n\n'
        '数据是每次专注的记录里**实时算出来**的，不额外存一份 —— '
        '所以改了统计口径，历史数据会自动按新口径重算。',
    bullets: const <String>[
      '今天专注了多久、完成了几个番茄',
      '近 7 天的柱状图',
      '近 7 天的时间都分给了哪些任务',
    ],
    tint: const Color(0xFF185FA5),
  ),
  ManualPage(
    icon: Icons.calendar_month_outlined,
    title: '课表',
    body: '在你的课表页面截**两张图**（上下两半，中间留一点重复），'
        'App 会把它们拼成一张完整的、识别出来，'
        '核对无误再存进手机。',
    bullets: const <String>[
      '两张之间要有大约五分之一屏的重复内容，App 靠它把接缝对上',
      '识别完可以逐格改课名 / 教室 / 周几 / 第几节',
      '填一次上课时间，全周的节次时间就排好了',
    ],
    tint: const Color(0xFF534AB7),
  ),
  const ManualPage(
    icon: Icons.shield_moon_outlined,
    title: '让提醒真的响',
    body: '这一项最容易被忽略，但它决定了**息屏之后到点还响不响**。\n\n'
        '去「我的 → 后台保活设置」，把四项都打开。',
    bullets: <String>[
      '通知权限',
      '精确闹钟',
      '省电策略设为「无限制」',
      '允许自启动',
    ],
  ),
];

/// 最后一页：本次更新。单独生成，方便 [kReleaseNotes] 直接改。
///
/// 标题跟 [kAppVersion] 走（**不是** [kManualVersion]，那个只管弹不弹）。
ManualPage releaseNotesPage() => ManualPage(
      icon: Icons.auto_awesome_outlined,
      title: 'v$kAppVersion 更新内容',
      body: '这一版主要动了课表 —— 能导入、能改、能删。',
      bullets: kReleaseNotes,
    );

/// 手册的全部页面（含最后一页「更新内容」）
List<ManualPage> manualPagesWithReleaseNotes() => <ManualPage>[
      ...kManualPages,
      releaseNotesPage(),
    ];
