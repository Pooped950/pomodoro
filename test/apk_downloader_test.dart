import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pomodoro/data/services/apk_downloader.dart';

/// APK 下载器 —— 它手里握着"装什么包"的最后一棒，所以三件事必须钉住：
///   1. 进度真实（UI 要显示百分比）
///   2. 半截文件绝不能被当成完整包（先写 .part，成功才改名）
///   3. sha256 对不上就当失败
void main() {
  /// 'hello' 的 sha256（固定值，免得测试自己算一遍）
  const String helloSha =
      '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('apk_dl_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('正常流：进度递增，落盘字节数等于 expectedSize', () async {
    final ApkDownloader d = ApkDownloader(
      client: _FakeClient(<List<int>>[
        utf8.encode('hel'),
        utf8.encode('lo'),
      ]),
    );
    final String dest = '${tmp.path}/a.apk';

    final List<ApkDownloadProgress> seen = <ApkDownloadProgress>[];
    await for (final ApkDownloadProgress p
        in d.download(url: 'https://x.test/a.apk', destPath: dest, expectedSize: 5)) {
      seen.add(p);
    }

    expect(seen, isNotEmpty);
    expect(seen.last.received, 5);
    expect(seen.last.fraction, 1.0);
    // 进度必须单调不减
    for (int i = 1; i < seen.length; i++) {
      expect(seen[i].received, greaterThanOrEqualTo(seen[i - 1].received));
    }
    expect(File(dest).readAsStringSync(), 'hello');
    expect(File('$dest.part').existsSync(), isFalse, reason: '成功时要清理临时文件');
  });

  test('Content-Length 缺失（expectedSize 0）→ 不算出 NaN，进度退化成字节数', () async {
    final ApkDownloader d = ApkDownloader(
      client: _FakeClient(<List<int>>[utf8.encode('he'), utf8.encode('llo')]),
    );

    final List<ApkDownloadProgress> seen = <ApkDownloadProgress>[];
    await for (final ApkDownloadProgress p in d.download(
        url: 'https://x.test/a.apk',
        destPath: '${tmp.path}/b.apk',
        expectedSize: 0)) {
      seen.add(p);
    }

    expect(seen.last.received, 5);
    for (final ApkDownloadProgress p in seen) {
      expect(p.fraction.isNaN, isFalse);
    }
  });

  test('中途异常 → 抛 ApkDownloadException，且不留下完整的目标文件', () async {
    final ApkDownloader d = ApkDownloader(
      client: _FakeClient(<List<int>>[utf8.encode('hel')], failAfter: 1),
    );
    final String dest = '${tmp.path}/c.apk';

    await expectLater(
      d
          .download(url: 'https://x.test/a.apk', destPath: dest, expectedSize: 5)
          .drain<void>(),
      throwsA(isA<ApkDownloadException>()),
    );

    expect(File(dest).existsSync(), isFalse, reason: '半截文件不能出现在目标路径上');
    expect(File('$dest.part').existsSync(), isFalse, reason: '失败要清掉 .part');
  });

  test('HTTP 404 → 抛 ApkDownloadException', () async {
    final ApkDownloader d =
        ApkDownloader(client: _FakeClient(<List<int>>[], statusCode: 404));

    await expectLater(
      d
          .download(
              url: 'https://x.test/none.apk',
              destPath: '${tmp.path}/d.apk',
              expectedSize: 10)
          .drain<void>(),
      throwsA(isA<ApkDownloadException>()),
    );
  });

  test('sha256 相符 → true；不符 / 半截文件 → false', () async {
    final File ok = File('${tmp.path}/ok.bin')..writeAsStringSync('hello');
    final File bad = File('${tmp.path}/bad.bin')..writeAsStringSync('hell');
    final File half = File('${tmp.path}/half.bin')..writeAsStringSync('hel');

    expect(await verifyApkSha256(ok.path, helloSha), isTrue);
    expect(await verifyApkSha256(bad.path, helloSha), isFalse);
    expect(await verifyApkSha256(half.path, helloSha), isFalse);
    expect(await verifyApkSha256('${tmp.path}/nope.bin', helloSha), isFalse);
  });

  test('校验大小写不敏感（远端可能给大写）', () async {
    final File f = File('${tmp.path}/up.bin')..writeAsStringSync('hello');

    expect(await verifyApkSha256(f.path, helloSha.toUpperCase()), isTrue);
  });

  test('clearStaleApkFiles：删掉残留的 .apk / .part，别的不动', () async {
    File('${tmp.path}/old.apk').writeAsStringSync('x');
    File('${tmp.path}/old.apk.part').writeAsStringSync('x');
    File('${tmp.path}/keep.txt').writeAsStringSync('x');

    await clearStaleApkFiles(tmp);

    expect(File('${tmp.path}/old.apk').existsSync(), isFalse);
    expect(File('${tmp.path}/old.apk.part').existsSync(), isFalse);
    expect(File('${tmp.path}/keep.txt').existsSync(), isTrue);
  });
}

/// 假 http.Client：按给定分片吐一个流；[failAfter] 指定在第几片之后抛错
class _FakeClient extends http.BaseClient {
  _FakeClient(this.chunks, {this.failAfter, this.statusCode = 200});

  final List<List<int>> chunks;
  final int? failAfter;
  final int statusCode;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final StreamController<List<int>> c = StreamController<List<int>>();
    final int? fail = failAfter; // 存成局部变量：public field 不做类型提升
    int sent = 0;
    for (final List<int> chunk in chunks) {
      c.add(chunk);
      sent++;
      if (fail != null && sent >= fail) break;
    }
    if (fail != null) {
      c.addError(const SocketException('连接被重置'));
    }
    unawaited(c.close());
    return http.StreamedResponse(c.stream, statusCode,
        contentLength: chunks.fold<int>(0, (int a, List<int> b) => a + b.length));
  }
}
