import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// 把解释文本渲染成能看的样子：公式用真正的排版，而不是露 LaTeX 源码。
///
/// 支持：
/// - `$$...$$` 独立成行的大公式（居中，过长可横向滑动）
/// - `$...$` 行内公式
/// - `**粗体**`、`` `行内代码` ``
/// - `# / ## / ###` 标题、`-` 或 `1.` 列表、``` 代码块
class RichContent extends StatelessWidget {
  const RichContent({
    super.key,
    required this.text,
    this.fontSize = 15,
    this.color = const Color(0xFF1F2430),
    this.height = 1.6,
  });

  final String text;
  final double fontSize;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontSize: fontSize, height: height, color: color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _blocks(text, base),
    );
  }
}

/// 列表页的一行预览：把公式换成占位词，避免露出 \frac 之类的源码
String plainPreview(String s) {
  var t = s
      .replaceAll(RegExp(r'\$\$[\s\S]*?\$\$'), '〔公式〕')
      .replaceAll(RegExp(r'\$[^$\n]*?\$'), '〔公式〕');
  t = t.replaceAll(RegExp(r'[#*`>_~]'), '').replaceAll(RegExp(r'\s+'), ' ');
  return t.trim();
}

List<Widget> _blocks(String src, TextStyle base) {
  final lines = src.replaceAll('\r\n', '\n').split('\n');
  final out = <Widget>[];
  final para = <String>[];

  void flush() {
    if (para.isEmpty) return;
    final txt = para.join('\n').trim();
    para.clear();
    if (txt.isEmpty) return;
    out.add(RichText(text: TextSpan(style: base, children: _inline(txt, base))));
  }

  var i = 0;
  while (i < lines.length) {
    final trimmed = lines[i].trim();

    if (trimmed.isEmpty) {
      flush();
      i++;
      continue;
    }

    // ``` 代码块
    if (trimmed.startsWith('```')) {
      flush();
      final buf = <String>[];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        buf.add(lines[i]);
        i++;
      }
      i++;
      out.add(_codeBlock(buf.join('\n'), base));
      continue;
    }

    // $$ 独立公式（单行或多行）
    if (trimmed.startsWith('\$\$')) {
      flush();
      final first = trimmed.substring(2).trim();
      if (first.length > 2 && first.endsWith('\$\$')) {
        out.add(_displayMath(first.substring(0, first.length - 2).trim(), base));
        i++;
      } else {
        final buf = <String>[first];
        i++;
        while (i < lines.length) {
          final cur = lines[i].trim();
          if (cur.endsWith('\$\$')) {
            buf.add(cur.substring(0, cur.length - 2).trim());
            i++;
            break;
          }
          buf.add(cur);
          i++;
        }
        out.add(_displayMath(buf.join(' ').trim(), base));
      }
      continue;
    }

    // 标题
    final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
    if (h != null) {
      flush();
      final level = h.group(1)!.length;
      final delta = level <= 1 ? 4.0 : (level == 2 ? 2.0 : 1.0);
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          h.group(2)!,
          style: base.copyWith(
            fontSize: base.fontSize! + delta,
            fontWeight: FontWeight.w600,
          ),
        ),
      ));
      i++;
      continue;
    }

    // 列表项
    final li = RegExp(r'^([-*+]\s+|\d+[.)]\s+)(.*)$').firstMatch(trimmed);
    if (li != null) {
      flush();
      final marker = li.group(1)!.trim();
      final dot = (marker == '-' || marker == '*' || marker == '+') ? '·' : marker;
      out.add(Padding(
        padding: const EdgeInsets.only(left: 10, bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dot, style: base.copyWith(color: base.color!.withAlpha(170))),
            const SizedBox(width: 6),
            Expanded(
              child: RichText(
                text: TextSpan(
                    style: base, children: _inline(li.group(2)!, base)),
              ),
            ),
          ],
        ),
      ));
      i++;
      continue;
    }

    para.add(lines[i].trimRight());
    i++;
  }
  flush();

  if (out.isEmpty) return [const SizedBox.shrink()];
  return out;
}

Widget _displayMath(String expr, TextStyle base) {
  if (expr.trim().isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Math.tex(
        expr,
        mathStyle: MathStyle.display,
        textStyle: base.copyWith(fontSize: base.fontSize! + 3),
      ),
    ),
  );
}

Widget _codeBlock(String code, TextStyle base) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 6),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFF6F7FB),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      code,
      style: base.copyWith(fontFamily: 'monospace', fontSize: 13, height: 1.45),
    ),
  );
}

List<InlineSpan> _inline(String text, TextStyle base) {
  final spans = <InlineSpan>[];
  final re = RegExp(r'\$\$(.+?)\$\$|\$([^$\n]+?)\$');
  var pos = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > pos) spans.addAll(_styled(text.substring(pos, m.start), base));
    final expr = (m.group(1) ?? m.group(2)) ?? '';
    if (expr.trim().isNotEmpty) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Math.tex(expr, mathStyle: MathStyle.text, textStyle: base),
      ));
    }
    pos = m.end;
  }
  if (pos < text.length) spans.addAll(_styled(text.substring(pos), base));
  if (spans.isEmpty) spans.add(TextSpan(text: text, style: base));
  return spans;
}

List<InlineSpan> _styled(String text, TextStyle base) {
  final out = <InlineSpan>[];
  final re = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`');
  var pos = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > pos) {
      out.add(TextSpan(text: text.substring(pos, m.start), style: base));
    }
    final bold = m.group(1);
    final code = m.group(2);
    if (bold != null) {
      out.add(TextSpan(
          text: bold, style: base.copyWith(fontWeight: FontWeight.w700)));
    } else if (code != null) {
      out.add(TextSpan(
        text: code,
        style: base.copyWith(
          fontFamily: 'monospace',
          fontSize: base.fontSize! - 1,
          backgroundColor: const Color(0xFFF1F2F7),
        ),
      ));
    }
    pos = m.end;
  }
  if (pos < text.length) {
    out.add(TextSpan(text: text.substring(pos), style: base));
  }
  return out;
}
