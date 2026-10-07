import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/app_info.dart';
import 'package:pomodoro/domain/update/update_decision.dart';
import 'package:pomodoro/domain/update/update_info.dart';
import 'package:pomodoro/presentation/providers/update_provider.dart';
import 'package:pomodoro/presentation/widgets/update_row.dart';

/// 「我的」页最下面那一行 —— 三种副标题 + 小红点。
/// 用户就是靠这一行知道"有没有新版"，文案错了他会以为永远是最新的。
void main() {
  final String sha = List<String>.filled(64, 'e').join();

  UpdateInfo info(int versionCode) => UpdateInfo(
        versionCode: versionCode,
        versionName: '9.9.9',
        apkUrl: 'https://gitee.com/o/r/raw/main/a.apk',
        sha256: sha,
        sizeBytes: 1024,
      );

  Future<void> pump(
    WidgetTester tester,
    UpdateState state, {
    VoidCallback? onTap,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateStateProvider.overrideWith(() => _FakeUpdateNotifier(state)),
        ],
        child: MaterialApp(
          home: Scaffold(body: UpdateRow(onTap: onTap)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('还没拿到版本信息 → 副标题是当前版本，没有小红点', (WidgetTester tester) async {
    await pump(tester, const UpdateState());

    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('当前版本 v$kAppVersion'), findsOneWidget);
    expect(find.byKey(UpdateRow.dotKey), findsNothing);
  });

  testWidgets('已是最新 → 「已是最新 · 当前版本」，没有小红点', (WidgetTester tester) async {
    await pump(
      tester,
      UpdateState(
        remote: info(kAppVersionCode),
        checkedAt: DateTime(2026, 10, 7, 18),
        action: UpdateAction.none,
      ),
    );

    expect(find.text('已是最新 · v$kAppVersion'), findsOneWidget);
    expect(find.byKey(UpdateRow.dotKey), findsNothing);
  });

  testWidgets('有新版本 → 「有新版本 vX」+ 小红点', (WidgetTester tester) async {
    await pump(
      tester,
      UpdateState(
        remote: info(kAppVersionCode + 1),
        checkedAt: DateTime(2026, 10, 7, 18),
        action: UpdateAction.silentHint,
      ),
    );

    expect(find.text('有新版本 v9.9.9'), findsOneWidget);
    expect(find.byKey(UpdateRow.dotKey), findsOneWidget);
  });

  testWidgets('点一下 → 触发回调（进「检查更新」页）', (WidgetTester tester) async {
    bool tapped = false;
    await pump(tester, const UpdateState(), onTap: () => tapped = true);

    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });
}

class _FakeUpdateNotifier extends UpdateNotifier {
  _FakeUpdateNotifier(this._state);

  final UpdateState _state;

  @override
  UpdateState build() => _state;

  @override
  Future<void> checkIfStale() async {}

  @override
  Future<void> checkNow() async {}
}
