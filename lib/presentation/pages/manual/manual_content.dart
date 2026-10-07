import 'package:flutter/material.dart';

/// 使用手册的**版本号**。
///
/// ## 这个数字是"弹不弹"的开关
///
/// 用户看过的手册版本存在 `settings` 里。每次启动比对：
///   - 存的和 [kManualVersion] **一样** → 不再弹
///   - 不一样（首次安装、或者版本升了）→ 再弹一次
///
/// 所以**每次发版要记得改这里**，并把 [kReleaseNotes] 换成这一版的新内容 ——
/// 这样老用户升级后会自动看到"这次更新了什么"，不用另做一套更新日志页。
///
/// 只改文案、不改功能的小版本可以不升这个号（免得天天弹）。
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

/// 本次版本的更新内容（手册最后一页）
///
/// ⚠️ 发版时和 [kManualVersion] 一起改。
const List<String> kReleaseNotes = <String>[
  '「任务」和「统计」合并成一页，顶部两个小标签切换，底部导航腾出一格给课表',
  '新增「课表」页：截两张课表截图，自动拼成一张完整的，本机离线识别，'
      '逐格核对之后再存进手机',
  '新增这份使用手册 —— 首次打开自动出现，之后可以在「我的」里随时翻',
];

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
ManualPage releaseNotesPage() => ManualPage(
      icon: Icons.auto_awesome_outlined,
      title: 'v$kManualVersion 更新内容',
      body: '这一版主要动了导航结构和课表。',
      bullets: kReleaseNotes,
    );

/// 手册的全部页面（含最后一页「更新内容」）
List<ManualPage> manualPagesWithReleaseNotes() => <ManualPage>[
      ...kManualPages,
      releaseNotesPage(),
    ];
