import 'dart:typed_data';

import 'package:flutter/services.dart';

/// 与 Android 原生侧通信：SAF 目录授权写文件 + 桌面小组件数据桥
class PlatformService {
  static const MethodChannel _ch = MethodChannel('wordlog/native');

  /// 应用私有文件目录，笔记图片存这里（不需要任何权限）
  static Future<String> filesDir() async =>
      await _ch.invokeMethod<String>('filesDir') ?? '';

  /// 把图片按相对路径写进已授权的导出目录（子目录自动创建）
  static Future<bool> writeBytes(
      String uri, String relativePath, Uint8List bytes) async {
    final r = await _ch.invokeMethod<bool>('writeBytes', {
      'uri': uri,
      'relativePath': relativePath,
      'bytes': bytes,
    });
    return r == true;
  }

  // ---------- SAF 导出 ----------

  /// 打开系统文件夹选择器，返回持久化授权的根 URI
  static Future<String?> pickDirectory() =>
      _ch.invokeMethod<String>('pickDirectory');

  /// 写入（已存在则覆盖）文件到已授权目录
  static Future<bool> writeFile(
      String uri, String fileName, String content) async {
    final r = await _ch.invokeMethod<bool>('writeFile', {
      'uri': uri,
      'fileName': fileName,
      'content': content,
    });
    return r == true;
  }

  /// 读取已授权目录下的文件内容（不存在返回 null）
  static Future<String?> readFile(String uri, String fileName) =>
      _ch.invokeMethod<String>('readFile', {
        'uri': uri,
        'fileName': fileName,
      });

  // ---------- 小组件 / 快捷记录 ----------

  /// 取出小组件或快捷入口暂存、尚未入库的词
  static Future<List<Map<String, dynamic>>> pending() async {
    final r = await _ch.invokeMethod<List<dynamic>>('getPending');
    if (r == null) return [];
    return r
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<void> clearPending() => _ch.invokeMethod('clearPending');

  /// 把今日统计推给小组件显示
  static Future<void> updateWidgetStats(int count, List<String> recent) =>
      _ch.invokeMethod('setWidgetStats', {
        'count': count,
        'recent': recent,
      });
}
