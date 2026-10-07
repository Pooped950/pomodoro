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
    test('★ major 更小才弹：1.9.0 → 2.0.0 弹，2.0.0 → 2.0.0 不弹', () {
      expect(shouldShowMajorUpdateDialog('1.9.0', '2.0.0'), isTrue);
      expect(shouldShowMajorUpdateDialog('2.0.0', '2.0.0'), isFalse);
      expect(shouldShowMajorUpdateDialog('2.1.0', '2.0.0'), isFalse);
    });

    test('小版本和补丁不弹（2.0.0 → 2.1.x）', () {
      expect(shouldShowMajorUpdateDialog('2.0.0', '2.1.0'), isFalse);
      expect(shouldShowMajorUpdateDialog('2.0.0', '2.0.5'), isFalse);
    });

    test('null / 脏数据不弹（全新安装或认不出，宁可少弹）', () {
      expect(shouldShowMajorUpdateDialog(null, '2.0.0'), isFalse);
      expect(shouldShowMajorUpdateDialog('abc', '2.0.0'), isFalse);
      expect(shouldShowMajorUpdateDialog('', '2.0.0'), isFalse);
    });

    test('跨多个大版本也弹（1.x 直接升 3.0.0）', () {
      expect(shouldShowMajorUpdateDialog('1.8.0', '3.0.0'), isTrue);
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
