import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// 下载失败（网络、HTTP 状态、写入、校验）——调用方统一按"可重试"处理
class ApkDownloadException implements Exception {
  const ApkDownloadException(this.message);

  final String message;

  @override
  String toString() => 'ApkDownloadException: $message';
}

/// 下载进度。[total] 为 0 表示**不知道总量**（服务端没给 Content-Length）：
/// 这时 [fraction] 恒为 0，界面改成显示"已下载 xx MB"。
class ApkDownloadProgress {
  const ApkDownloadProgress({required this.received, required this.total});

  final int received;
  final int total;

  double get fraction {
    if (total <= 0) return 0;
    return (received / total).clamp(0.0, 1.0);
  }
}

/// 把 APK 下到本地。
///
/// ## 为什么先写 `.part` 再改名
///
/// 这条链路的尽头是"让系统装这个包"。半截文件如果落在目标路径上，
/// 一次意外的进程死亡就可能被当成完整包递给安装器。
/// 所以：只有**完整读完并核对过**才改名到 [destPath]；任何失败都删掉 `.part`。
///
/// ## 为什么要 sha256
///
/// 下载过程可能被中间设备篡改/截断。校验值来自版本文件，对不上就当失败。
class ApkDownloader {
  ApkDownloader({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Stream<ApkDownloadProgress> download({
    required String url,
    required String destPath,
    required int expectedSize,
  }) async* {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw const ApkDownloadException('只允许从 https 地址下载');
    }

    final File part = File('$destPath.part');
    final File dest = File(destPath);
    IOSink? sink;
    try {
      final http.StreamedResponse res =
          await _client.send(http.Request('GET', uri));
      if (res.statusCode != 200) {
        throw ApkDownloadException('下载失败（HTTP ${res.statusCode}）');
      }

      if (dest.existsSync()) dest.deleteSync();
      if (part.existsSync()) part.deleteSync();
      await part.parent.create(recursive: true);
      sink = part.openWrite();

      final int total = expectedSize > 0 ? expectedSize : (res.contentLength ?? 0);
      int received = 0;

      await for (final List<int> chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        yield ApkDownloadProgress(received: received, total: total);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (expectedSize > 0 && received != expectedSize) {
        throw ApkDownloadException('下载不完整（$received/$expectedSize 字节）');
      }
      await part.rename(destPath);
    } on ApkDownloadException {
      rethrow;
    } catch (e) {
      throw ApkDownloadException('下载出错：$e');
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {
          // 已经出错了，关不上也不影响结论
        }
      }
      if (part.existsSync()) {
        try {
          part.deleteSync();
        } catch (_) {
          // 删不掉就留在临时目录里，下次启动会被 clearStaleApkFiles 清掉
        }
      }
    }
  }
}

/// 校验文件 sha256（大小写不敏感）。文件不存在 / 读不动 → false。
Future<bool> verifyApkSha256(String path, String expectedSha256) async {
  final File f = File(path);
  if (!f.existsSync()) return false;
  try {
    final Digest digest = await sha256.bind(f.openRead()).first;
    return digest.toString().toLowerCase() ==
        expectedSha256.trim().toLowerCase();
  } catch (_) {
    return false;
  }
}

/// 清掉上次残留的下载文件（App 启动时调一次）。
///
/// 只删 `.apk` / `.part`：临时目录里还可能有别的插件在用的东西。
Future<void> clearStaleApkFiles(Directory dir) async {
  if (!dir.existsSync()) return;
  try {
    await for (final FileSystemEntity e in dir.list()) {
      if (e is! File) continue;
      final String name = e.path.toLowerCase();
      if (!name.endsWith('.apk') && !name.endsWith('.part')) continue;
      try {
        e.deleteSync();
      } catch (_) {
        // 删不掉就留着，不值得打断启动
      }
    }
  } catch (_) {
    // 目录列不动（权限等）也不该影响启动
  }
}
