import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/app_info.dart';
import 'package:pomodoro/presentation/pages/manual/manual_content.dart';

/// 使用手册内容的冒烟测试。
///
/// 手册是**纯内容**，没有逻辑可测，但它有两个容易出错的地方值得钉住：
///   1. 每一页都得有标题和正文 —— 漏填一页在界面上就是一片空白
///   2. 最后一页必须是「本次更新」，而且标题里带**当前 App 版本** ——
///      手册里显示的版本要跟 [kAppVersion] 走；早先误用 [kManualVersion]
///      （那是"弹不弹"的记账值），结果 2.x 的 App 里手册写着 v1.9.0
void main() {
  group('使用手册内容', () {
    test('★ 每一页都有标题和正文（漏了在界面上就是一片空白）', () {
      final List<ManualPage> pages = manualPagesWithReleaseNotes();

      expect(pages.length, greaterThanOrEqualTo(5),
          reason: '手册要覆盖：介绍 / 计时 / 任务 / 统计 / 课表 / 保活 / 更新');

      for (final ManualPage p in pages) {
        expect(p.title.trim(), isNotEmpty, reason: '有页面缺标题');
        expect(p.body.trim(), isNotEmpty, reason: '「${p.title}」缺正文');
      }
    });

    test('★ 最后一页是「本次更新」，标题里带当前 App 版本', () {
      final List<ManualPage> pages = manualPagesWithReleaseNotes();
      final ManualPage last = pages.last;

      expect(last.title, contains(kAppVersion),
          reason: '手册里显示的版本要跟 App 版本（kAppVersion）走，'
              '不能再用 kManualVersion 显示');
      expect(last.title, isNot(contains(kManualVersion)),
          reason: 'kManualVersion 只是"弹不弹"的开关，不该出现在用户看到的文案里');
      expect(kReleaseNotes, isNotEmpty,
          reason: '更新内容不能是空的 —— 否则用户升级后看到的是一片空白');
    });

    test('手册内容版本号是形如 x.y.z 的字符串（只管弹不弹，不显示给用户）', () {
      expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(kManualVersion), isTrue);
    });
  });
}
