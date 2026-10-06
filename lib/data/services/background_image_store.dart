import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 背景图片的**落盘管理**。
///
/// ## 为什么必须把选的照片复制一份
///
/// `image_picker` 返回的是**相册临时缓存**里的路径。系统随时可能清掉它，
/// 用户也可能"编辑原图"导致路径失效。直接把那个路径存进设置里，
/// 过一阵子背景就会变成一张白板 —— 而且用户完全不知道为什么。
///
/// 所以选图后立刻复制到应用私有目录（`getApplicationDocumentsDirectory`），
/// 存自己那份的路径。应用私有目录不会被系统清理，卸载才会删。
///
/// ## 为什么还要负责删除
///
/// 每换一次背景图就多留一份拷贝，换十次就是十张几 MB 的照片躺在应用目录里。
/// 所以换图/清除时把**上一份**删掉（见 [replaceOld]）。
/// 只删自己目录里的、且不再是当前使用的那份 —— 绝不碰用户相册里的原图。
class BackgroundImageStore {
  const BackgroundImageStore();

  /// 应用私有目录下的背景图目录名
  static const String _dirName = 'backgrounds';

  /// 把 [sourcePath] 复制进应用私有目录，返回新路径。
  ///
  /// 用时间戳当文件名：避免"选了同名文件导致覆盖"，
  /// 也让旧文件能被识别出来（旧文件一定比新文件的时间戳小）。
  Future<String> importFrom(String sourcePath) async {
    final Directory root = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${root.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);

    final String ext = _extensionOf(sourcePath);
    final String target =
        '${dir.path}/bg_${DateTime.now().millisecondsSinceEpoch}$ext';

    await File(sourcePath).copy(target);
    return target;
  }

  /// 删除上一张背景图（如果它不再被使用）。
  ///
  /// [previousPath] 是即将被替换掉的路径，[keepPath] 是接下来要用的路径。
  /// 两者相同就不动 —— 防止"用户只是改了暗度，却把正在用的图删了"。
  ///
  /// **只删自己目录里的文件**：万一 [previousPath] 是用户相册的原始路径
  /// （早期版本存错过），删掉就是删用户的照片，那是不可接受的。
  Future<void> replaceOld(String? previousPath, {String? keepPath}) async {
    if (previousPath == null || previousPath.isEmpty) return;
    if (previousPath == keepPath) return;

    try {
      final Directory root = await getApplicationDocumentsDirectory();
      final String ownDir = '${root.path}/$_dirName';
      if (!previousPath.startsWith(ownDir)) return; // 不是我们的文件，不碰

      final File f = File(previousPath);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 删不掉不是致命问题（最多留一份垃圾），绝不能因此让界面报错
    }
  }

  /// 图片是否还在（文件被外部删掉时界面要能回退，而不是显示白板）
  Future<bool> exists(String? path) async {
    if (path == null || path.isEmpty) return false;
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  static String _extensionOf(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '.jpg';
    final String ext = path.substring(dot).toLowerCase();
    // 只接受常见图片扩展名，避免把奇怪的后缀带进来
    const List<String> allowed = <String>['.jpg', '.jpeg', '.png', '.webp'];
    return allowed.contains(ext) ? ext : '.jpg';
  }
}

/// 背景图落盘服务。
///
/// 这个 provider **不需要在 main() 里 override** —— 它不依赖数据库，
/// 直接构造即可（与仓储类不同，那些必须注入真实的 Database 实例）。
final backgroundImageStoreProvider =
    Provider<BackgroundImageStore>((Ref ref) => const BackgroundImageStore());
