import 'package:flutter/material.dart';

import '../../../core/app_info.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/motion_tokens.dart';
import '../../widgets/glass_primary_button.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/motion_scope.dart';
import 'manual_content.dart';

/// 弹出使用手册 —— **屏幕正中央的液态玻璃弹窗 + 上下滑动翻页**。
///
/// ## 为什么是居中弹窗而不是底部弹层
///
/// 用户的要求是"正中间弹出"。底部弹层是**操作菜单**的语言（"从这里选一个"），
/// 而手册是**一次性读完的说明**，居中更像"翻开一本册子"，也和 App 里
/// 其它对话框（新建任务、改课节）是同一类东西。
///
/// ## 上下滑动 → 不能用底部弹层的拖拽
///
/// 顺带解决了一个坑：底部弹层默认"往下拖 = 关掉"，会和上下翻页抢同一个手势。
/// 改成居中弹窗之后这个冲突自然没了（弹窗没有拖拽关闭）。
///
/// ## 动效
///
/// 从**中心**缩放展开（0.92 → 1）+ 淡入，曲线和时长全部走 `motion_tokens` ——
/// 和「任务页三个点」那套上下文菜单是同一个做法，全 App 一套语言。
/// 退场比进场快（[Motion.press] 量级），收起来不该拖泥带水。
Future<void> showManualDialog(
  BuildContext context, {
  bool isFirstLaunch = false,
}) {
  final Motion motion = MotionScope.resolve(context);

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭使用手册',
    // 比默认的 black54 淡一些：玻璃弹窗不需要那么重的压暗，
    // 而且背后的页面还要透出来一点，玻璃才看得出是玻璃
    barrierColor: Colors.black.withValues(alpha: 0.30),
    transitionDuration: motion.pageEnter,
    pageBuilder: (
      BuildContext _,
      Animation<double> _,
      Animation<double> _,
    ) =>
        ManualDialogBody(isFirstLaunch: isFirstLaunch),
    transitionBuilder: (
      BuildContext _,
      Animation<double> animation,
      Animation<double> _,
      Widget child,
    ) {
      final Animation<double> curved = CurvedAnimation(
        parent: animation,
        curve: MotionTokens.emphasized,
        reverseCurve: MotionTokens.emphasizedIn,
      );
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          // 透明度比缩放先到位，避免"已经展开完了还在淡入"
          curve: const Interval(0, 0.5, curve: Curves.easeOut),
        ),
        child: ScaleTransition(
          alignment: Alignment.center,
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 手册弹窗的本体（单独暴露出来是为了能单测 / 复用）
class ManualDialogBody extends StatelessWidget {
  const ManualDialogBody({super.key, this.isFirstLaunch = false});

  final bool isFirstLaunch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            // 和页面内容一样限宽，大屏上不会拉成一条
            maxWidth: kMaxContentWidth,
            // 留出上下边距，让用户看到"这是浮在页面上的一层"
            maxHeight: MediaQuery.of(context).size.height * 0.76,
          ),
          // ⚠️ 必须有 Material 祖先：`showGeneralDialog` 不像 `showDialog` 那样
          // 自带一层，缺了它里面的 Text 会被 Flutter 标上黄色下划线
          // （"文字没有 Material 祖先"的提示），真机上看得见。
          // 用透明 Material：只要"祖先"这个身份，不要它铺底色
          // （底色交给 GlassSurface 的玻璃）。
          child: Material(
            type: MaterialType.transparency,
            child: GlassSurface(
              radius: AppRadius.card,
              padding: const EdgeInsets.all(AppSpacing.item),
              child: ManualContent(isFirstLaunch: isFirstLaunch),
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹窗里的内容：标题 + 上下翻页 + 页码条 + 按钮
class ManualContent extends StatefulWidget {
  const ManualContent({super.key, this.isFirstLaunch = false});

  final bool isFirstLaunch;

  @override
  State<ManualContent> createState() => _ManualContentState();
}

class _ManualContentState extends State<ManualContent> {
  final PageController _controller = PageController();

  late final List<ManualPage> _pages = manualPagesWithReleaseNotes();

  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _pages.length - 1;

  void _next() {
    if (_isLast) {
      Navigator.of(context).maybePop();
      return;
    }
    _controller.nextPage(
      duration: MotionScope.resolve(context).navSwitch,
      curve: MotionTokens.emphasized,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                widget.isFirstLaunch ? '欢迎使用' : '使用手册',
                style: text.titleMedium,
              ),
            ),
            Text(
              'v$kAppVersion',
              style: text.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.tight),

        // 上下翻页：指示条竖在右侧，一眼看出"还有几页、翻到哪了"
        Flexible(
          child: Row(
            children: <Widget>[
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  scrollDirection: Axis.vertical,
                  itemCount: _pages.length,
                  onPageChanged: (int i) => setState(() => _index = i),
                  itemBuilder: (BuildContext _, int i) =>
                      _ManualPageView(page: _pages[i]),
                ),
              ),
              _VerticalDots(count: _pages.length, index: _index),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.tight),
        Row(
          children: <Widget>[
            // 只有首启才给「跳过」—— 从「关于」翻手册时没必要跳过
            if (!_isLast && widget.isFirstLaunch) ...<Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('跳过'),
              ),
              const SizedBox(width: AppSpacing.tight),
            ],
            // ⚠️ 这里**不能**用裸的 FilledButton：App 的主题给它设了
            // `minimumSize: Size.fromHeight(...)`（最小宽度 = 无限），
            // 放进 Row 里会被撑到屏幕外 —— 表现就是"按钮不见了"。
            // 用 App 自己的玻璃主按钮（按内容 + Expanded 排布）。
            // 高度用它自己的默认值，别改小 —— 它的内部排版（图标 + 文字 +
            // 三层玻璃）是按 `kPrimaryButtonHeight` 调的。
            Expanded(
              child: GlassPrimaryButton(
                key: ValueKey<String>(_isLast ? 'manual-done' : 'manual-next'),
                label: _isLast ? '开始使用' : '继续',
                icon: _isLast
                    ? Icons.check_rounded
                    : Icons.keyboard_arrow_down_rounded,
                accent: scheme.primary,
                onPressed: _next,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 手册的一页
class _ManualPageView extends StatelessWidget {
  const _ManualPageView({required this.page});

  final ManualPage page;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final Color tint = page.tint ?? scheme.primary;

    // ⚠️ 这里**不能**用能滚的 SingleChildScrollView：外面已经是上下翻页的
    // PageView，同方向的滚动会互相抢手势 —— 用户一拖就被内层吃掉，页永远翻不过去。
    //
    // 所以套一个**禁用滚动**的 SingleChildScrollView 当保险：它给子节点无界高度，
    // 万一某页内容偏高也不会抛溢出警告（超出部分裁掉），同时不参与手势竞争。
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 图标放在一块淡色圆角块里 —— 和空状态卡片是同一套处理
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.cardMedium),
            ),
            child: Icon(page.icon, size: 24, color: tint),
          ),
          const SizedBox(height: AppSpacing.item),
          Text(page.title, style: text.titleLarge),
          const SizedBox(height: AppSpacing.tight),
          _RichBody(page.body, base: text.bodyMedium, tint: tint),

          if (page.bullets.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.item),
            for (final String b in page.bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.75),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        b,
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.78),
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 正文里 `**…**` 包住的部分渲染成强调色 + 稍粗
///
/// 为什么不用 Markdown 库：手册就这一种标记，为它引一个包不值当。
/// 分成奇数段（1、3、5…）就是被 `**` 包住的那些。
class _RichBody extends StatelessWidget {
  const _RichBody(this.raw, {required this.base, required this.tint});

  final String raw;
  final TextStyle? base;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<String> parts = raw.split('**');

    return RichText(
      text: TextSpan(
        style: base?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.72),
          height: 1.7,
        ),
        children: <InlineSpan>[
          for (int i = 0; i < parts.length; i++)
            TextSpan(
              text: parts[i],
              style: i.isOdd
                  ? TextStyle(color: tint, fontWeight: FontWeight.w600)
                  : null,
            ),
        ],
      ),
    );
  }
}

/// 竖在右侧的页码指示 —— 上下翻页时用竖条，方向才和手势一致
///
/// 当前页是一根小胶囊，其余是圆点，和底部导航条的指示器同源。
class _VerticalDots extends StatelessWidget {
  const _VerticalDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Motion motion = MotionScope.of(context);

    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.tight),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (int i = 0; i < count; i++)
            AnimatedContainer(
              duration: motion.standard,
              curve: MotionTokens.emphasized,
              margin: const EdgeInsets.symmetric(vertical: 3),
              width: 6,
              height: i == index ? 18 : 6,
              decoration: BoxDecoration(
                color: i == index
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
        ],
      ),
    );
  }
}
