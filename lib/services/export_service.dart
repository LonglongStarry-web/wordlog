import 'package:intl/intl.dart';

import '../models/note.dart';
import '../models/term.dart';

class ExportService {
  static const List<String> weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  static String weekdayOf(DateTime d) => weekdays[d.weekday - 1];

  /// 按天分组生成 Markdown。terms 需按时间倒序或任意顺序，内部会排序。
  /// [notes] 是 termId -> 该词条下的笔记列表，传入后会一并导出（图片引用为 images/ 相对路径）。
  static String buildMarkdown(
    List<Term> terms, {
    String? title,
    Map<int, List<Note>>? notes,
  }) {
    if (terms.isEmpty) return '';
    final sorted = [...terms]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final buf = StringBuffer();
    buf.writeln(title ?? '# 我的词记本');
    buf.writeln();

    final byDay = <String, List<Term>>{};
    for (final t in sorted) {
      final k = DateFormat('yyyy-MM-dd').format(t.createdAt);
      byDay.putIfAbsent(k, () => []).add(t);
    }

    for (final day in byDay.keys.toList()..sort()) {
      final list = byDay[day]!;
      buf.writeln('## $day ${weekdayOf(list.first.createdAt)}');
      buf.writeln();
      for (final t in list) {
        buf.writeln('### ${t.name}');
        final ctx = t.context?.trim() ?? '';
        if (ctx.isNotEmpty) {
          buf.writeln('> $ctx');
          buf.writeln();
        }
        if (!t.isExplained) {
          buf.writeln('（待解释）');
          buf.writeln();
        } else {
          if (_v(t.definition).isNotEmpty) {
            buf.writeln('**专业定义**');
            buf.writeln();
            buf.writeln(_v(t.definition));
            buf.writeln();
          }
          if (_v(t.analogy).isNotEmpty) {
            buf.writeln('**通俗解释**');
            buf.writeln();
            buf.writeln(_v(t.analogy));
            buf.writeln();
          }
          if (_v(t.example).isNotEmpty) {
            buf.writeln('**例子**');
            buf.writeln();
            buf.writeln(_v(t.example));
            buf.writeln();
          }
          if (_v(t.extension).isNotEmpty) {
            buf.writeln('**延伸**：${_v(t.extension)}');
            buf.writeln();
          }
        }

        final tid = t.id;
        final own = (tid == null) ? null : notes?[tid];
        if (own != null && own.isNotEmpty) {
          buf.writeln('**我的笔记**');
          buf.writeln();
          for (final n in own) {
            final text = n.content.trim();
            if (text.isNotEmpty) {
              buf.writeln(text);
              buf.writeln();
            }
            for (final img in n.images) {
              buf.writeln('![](${imageRef(img)})');
              buf.writeln();
            }
          }
        }

        if (t.tags.isNotEmpty) {
          buf.writeln(t.tags.map((e) => '#$e').join(' '));
          buf.writeln();
        }
        buf.writeln();
      }
    }
    return '${buf.toString().trimRight()}\n';
  }

  static String monthFileName(DateTime d) => '${DateFormat('yyyy-MM').format(d)}.md';

  /// 追加合并：把新内容并入已有文件（同月多次导出）。
  static String merge(String existing, String incoming) {
    if (existing.trim().isEmpty) return incoming;
    final existingDays = <String>{};
    for (final line in existing.split('\n')) {
      if (line.startsWith('## ')) {
        existingDays.add(line.substring(3).split(' ').first);
      }
    }
    final incomingLines = incoming.split('\n');
    final out = <String>[];
    var skipping = false;
    for (final line in incomingLines) {
      if (line.startsWith('## ')) {
        final day = line.substring(3).split(' ').first;
        skipping = existingDays.contains(day);
        if (skipping) continue;
      }
      if (skipping && line.startsWith('# ')) skipping = false;
      if (!skipping) out.add(line);
    }
    final body = out.join('\n').trim();
    if (body.isEmpty) return existing;
    return '${existing.trimRight()}\n\n$body\n';
  }

  /// 导出时图片放在导出目录下的 images/ 子目录里
  static String imageRef(String absPath) {
    final name = absPath.split(RegExp(r'[\\/]')).last;
    return 'images/$name';
  }

  static String _v(String? s) => (s ?? '').trim();
}
