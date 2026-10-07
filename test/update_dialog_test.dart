import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/app_info.dart';
import 'package:pomodoro/presentation/pages/manual/update_dialog.dart';

/// 大版本更新弹窗 —— 「大版本才弹」的判定 + 弹窗内容。
///
/// 用户 2026-10-07 要求：大版本更新后要有更新说明弹窗；
/// 小版本/补丁不该烦人。
void main() {
  group('shouldShowMajorUpdateDialog', () {
    bool call({
      required bool fresh,
      required String? seen,
      String current = '2.0.0',
    }) =>
        shouldShowMajorUpdateDialog(
          isFreshInstall: fresh,
          seenVersion: seen,
          currentVersion: current,
        );

    test('★ major 更小才弹：1.9.0 → 2.0.0 弹，2.0.0 → 2.0.0 不弹', () {
      expect(call(fresh: false, seen: '1.9.0'), isTrue);
      expect(call(fresh: false, seen: '2.0.0'), isFalse);
      expect(call(fresh: false, seen: '2.1.0'), isFalse);
    });

    test('★ 键不存在的老用户也要弹（1.8.0 → 2.0.0 的真实升级路径）', () {
      // 真机实测踩到过：早先把 null 当"全新安装"直接不弹，
      // 结果所有 1.8.0 升上来的用户永远看不到更新说明（交接文档 §4.8）
      expect(call(fresh: false, seen: null), isTrue);
    });

    test('全新安装不弹（手册会讲），不管本地记过什么', () {
      expect(call(fresh: true, seen: null), isFalse);
      expect(call(fresh: true, seen: '1.8.0'), isFalse);
    });

    test('小版本和补丁不弹（2.0.0 → 2.1.x）', () {
      expect(call(fresh: false, seen: '2.0.0', current: '2.1.0'), isFalse);
      expect(call(fresh: false, seen: '2.0.0', current: '2.0.5'), isFalse);
    });

    test('脏数据不弹（宁可少弹，不要错弹）', () {
      expect(call(fresh: false, seen: 'abc'), isFalse);
      expect(call(fresh: false, seen: ''), isFalse);
    });

    test('跨多个大版本也弹（1.x 直接升 3.0.0）', () {
      expect(call(fresh: false, seen: '1.8.0', current: '3.0.0'), isTrue);
    });

    test('majorVersionOf：正常解析；脏数据/null 返回 null', () {
      expect(majorVersionOf('2.0.1'), 2);
      expect(majorVersionOf(' 3.4.5 '), 3);
      expect(majorVersionOf('abc'), isNull);
      expect(majorVersionOf(''), isNull);
      expect(majorVersionOf(null), isNull);
    });
  });

  group('更新弹窗内容', () {
    testWidgets('标题带当前版本，列出更新要点，按钮能关', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorSchemeSeed: const Color(0xFF3A6EA5)),
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (BuildContext buttonContext) => FilledButton(
                onPressed: () => showUpdateDialog(buttonContext),
                child: const Text('打开'),
              ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('v$kAppVersion 更新了什么'), findsOneWidget);
      for (final String note in kMajorUpdateNotes) {
        expect(find.textContaining(note.substring(0, 8)), findsOneWidget);
      }

      await tester.tap(find.text('开始使用'));
      await tester.pumpAndSettle();
      expect(find.text('v$kAppVersion 更新了什么'), findsNothing);
    });
  });
}
