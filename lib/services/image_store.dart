import 'dart:io';

import 'package:image_picker/image_picker.dart';

import 'platform_service.dart';

/// 笔记图片统一存放在应用私有目录，不需要任何系统权限
class ImageStore {
  static Future<String> root() async {
    final base = await PlatformService.filesDir();
    final dir = Directory('$base/notes_img');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  /// 选一张图（相册或拍照）并复制到私有目录，返回绝对路径；取消返回 null
  static Future<String?> pickAndSave(ImageSource source) async {
    final x = await ImagePicker()
        .pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (x == null) return null;
    final dir = await root();
    final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final dest = '$dir/$name';
    await File(x.path).copy(dest);
    return dest;
  }

  static Future<void> deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
