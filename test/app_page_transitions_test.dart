import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/theme/app_page_transitions.dart';

/// 页面转场的回归测试。
///
/// ## 为什么要有这个测试
///
/// 2026-10-06 真机/模拟器全 App 每一页整体左偏 ~20dp、屏幕右侧露出黑边，
/// 排查了一整天（窗口 frame、视图层级、SurfaceFlinger 图层全部正常），
/// 最后发现是 [buildAppPageTransition] 的"让位"Tween 把 begin/end 写反了：
/// 常态（secondaryAnimation=0，本页是顶层、无遮挡）被错误地放在了
/// `Offset(-0.05, 0)`（左移 5% 宽度）—— 每一页从出生起就带着这个位移。
/// 位移量 = 屏宽 × 5%，不同设备上都约等于 20dp，极具迷惑性。
/// 这里把"常态必须零位移"和"被遮挡时才左移"两个状态都钉死。
void main() {
  // 把转场包起来 pump 进测试树，返回时收集所有 FractionalTranslation
  // （SlideTransition 内部用 FractionalTranslation 实现位移）
  Future<List<Offset>> pumpTransition(
    WidgetTester tester, {
    required double primary,
    required double secondary,
  }) async {
    final controller1 = AnimationController(vsync: tester, value: primary);
    final controller2 = AnimationController(vsync: tester, value: secondary);
    final translations = <Offset>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (BuildContext context) => buildAppPageTransition(
            context,
            controller1,
            controller2,
            const SizedBox(width: 1000, height: 100),
          ),
        ),
      ),
    );
    tester
        .widgetList<FractionalTranslation>(find.byType(FractionalTranslation))
        .forEach((w) => translations.add(w.translation));
    controller1.dispose();
    controller2.dispose();
    return translations;
  }

  testWidgets('常态（页面在顶层、无遮挡）不得有任何位移', (WidgetTester tester) async {
    final translations = await pumpTransition(
      tester,
      primary: 1, // 已完成进场
      secondary: 0, // 没有任何页面盖在头上 —— 这是每一页的常态
    );
    expect(translations, isNotEmpty);
    for (final t in translations) {
      expect(t, Offset.zero,
          reason: '常态下出现位移 $t —— 这正是 2026-10-06 全 App 左偏 20dp 的回归形态');
    }
  });

  testWidgets('被新页面盖住时向左让位 5%，且新页从右侧 22% 滑入', (WidgetTester tester) async {
    // 进场起点：新页应在右侧 22% 处
    final entering = await pumpTransition(tester, primary: 0, secondary: 0);
    expect(entering.last, const Offset(0.22, 0));

    // 让位终点：本页被盖住时应左移 5% 宽度
    final covered = await pumpTransition(tester, primary: 1, secondary: 1);
    expect(covered.first, const Offset(-0.05, 0));
  });
}
