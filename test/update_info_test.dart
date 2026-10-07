import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/update/update_info.dart';

/// 版本文件（`version.json`）的解析 —— 这是**外部输入**，
/// 容错是第一原则：任何字段不合法都不能让 App 崩，也不能弹错误给用户。
void main() {
  final String sha = List<String>.filled(64, 'a').join();

  String raw(Map<String, Object?> overrides) => jsonEncode(<String, Object?>{
        'versionCode': 5,
        'versionName': '2.1.0',
        'apkUrl':
            'https://gitee.com/pooped950/pomodoro-dist/raw/main/pomodoro-v2.1.0.apk',
        'sha256': sha,
        'sizeBytes': 86439447,
        'publishedAt': '2026-10-08T12:00:00+08:00',
        'notes': <String>['一', '二'],
        'policy': 'prompt',
        'downloadPage': 'https://gitee.com/pooped950/pomodoro-dist',
        ...overrides,
      });

  test('合法 JSON：所有字段都读出来', () {
    final UpdateInfo? info = UpdateInfo.tryParse(raw(const <String, Object?>{}));

    expect(info, isNotNull);
    expect(info!.versionCode, 5);
    expect(info.versionName, '2.1.0');
    expect(info.sha256, sha);
    expect(info.sizeBytes, 86439447);
    expect(info.policy, UpdatePolicy.prompt);
    expect(info.notes, <String>['一', '二']);
    expect(info.publishedAt, DateTime.parse('2026-10-08T12:00:00+08:00'));
    expect(info.downloadPage, 'https://gitee.com/pooped950/pomodoro-dist');
  });

  test('publishedAt 是脏日期 → 解析成 null，不抛异常', () {
    final UpdateInfo? info =
        UpdateInfo.tryParse(raw(const <String, Object?>{'publishedAt': '昨天'}));

    expect(info, isNotNull);
    expect(info!.publishedAt, isNull);
  });

  test('versionCode 为 0 / 负数 / 字符串 / null → 整条当作没有版本信息', () {
    expect(UpdateInfo.tryParse(raw(const <String, Object?>{'versionCode': 0})),
        isNull);
    expect(UpdateInfo.tryParse(raw(const <String, Object?>{'versionCode': -3})),
        isNull);
    expect(UpdateInfo.tryParse(raw(const <String, Object?>{'versionCode': '5'})),
        isNull);
    expect(UpdateInfo.tryParse(raw(const <String, Object?>{'versionCode': null})),
        isNull);
  });

  test('sizeBytes 缺失/非正数 → 当作没有版本信息（下载前要拿它查空间）', () {
    expect(UpdateInfo.tryParse(raw(const <String, Object?>{'sizeBytes': 0})),
        isNull);
    expect(UpdateInfo.tryParse(raw(const <String, Object?>{'sizeBytes': null})),
        isNull);
  });

  test('sha256 不是 64 位十六进制 → 当作没有版本信息（否则校验形同虚设）', () {
    expect(UpdateInfo.tryParse(raw(const <String, Object?>{'sha256': 'abc'})),
        isNull);
    expect(
        UpdateInfo.tryParse(
            raw(<String, Object?>{'sha256': 'Z' * 64})), // 非 hex 字符
        isNull);
  });

  test('apkUrl 非 https / 域名不在白名单 / 后缀伪装 → 一律拒绝', () {
    const List<String> bad = <String>[
      'http://gitee.com/x/y.apk',
      'https://evil.example.com/y.apk',
      'https://gitee.com.evil.com/y.apk',
      'not a url',
      '',
    ];
    for (final String url in bad) {
      expect(UpdateInfo.tryParse(raw(<String, Object?>{'apkUrl': url})), isNull,
          reason: '$url 不该被接受');
    }
  });

  test('apkUrl 是 gitee.com 的子域 → 接受', () {
    final UpdateInfo? info = UpdateInfo.tryParse(raw(const <String, Object?>{
      'apkUrl': 'https://raw.gitee.com/a/b.apk',
    }));

    expect(info, isNotNull);
  });

  test('notes 空数组 → 空列表；非字符串元素被丢掉；缺失 → 空列表', () {
    expect(
        UpdateInfo.tryParse(raw(const <String, Object?>{'notes': <Object?>[]}))!
            .notes,
        isEmpty);
    expect(
        UpdateInfo.tryParse(raw(const <String, Object?>{
          'notes': <Object?>['ok', 3],
        }))!
            .notes,
        <String>['ok']);
    expect(UpdateInfo.tryParse(raw(const <String, Object?>{'notes': null}))!.notes,
        isEmpty);
  });

  test('policy 认不出 → 退回 silent（宁可少弹，不要错弹）', () {
    expect(
        UpdateInfo.tryParse(raw(const <String, Object?>{'policy': 'nonsense'}))!
            .policy,
        UpdatePolicy.silent);
    expect(UpdateInfo.tryParse(raw(const <String, Object?>{'policy': null}))!.policy,
        UpdatePolicy.silent);
  });

  test('未知字段忽略；可选项缺失走默认', () {
    final UpdateInfo? info = UpdateInfo.tryParse(raw(const <String, Object?>{
      'unknownField': 42,
      'downloadPage': null,
      'publishedAt': null,
    }));

    expect(info, isNotNull);
    expect(info!.downloadPage, isNull);
    expect(info.publishedAt, isNull);
    expect(info.policy, UpdatePolicy.prompt); // 显式传了的字段不受影响
  });

  test('整体不是 JSON / 是数组 / versionName 缺失 → 返回 null', () {
    expect(UpdateInfo.tryParse('not json'), isNull);
    expect(UpdateInfo.tryParse('[1,2,3]'), isNull);
    expect(UpdateInfo.tryParse(raw(const <String, Object?>{'versionName': null})),
        isNull);
  });
}
