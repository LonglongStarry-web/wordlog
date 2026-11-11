import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/term.dart';

class AiConfig {
  final String baseUrl;
  final String apiKey;
  final String model;

  const AiConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  bool get ready =>
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;
}

class ExplainedTerm {
  final String term;
  final String definition;
  final String analogy;
  final String example;
  final String extension;

  const ExplainedTerm({
    required this.term,
    required this.definition,
    required this.analogy,
    required this.example,
    required this.extension,
  });
}

class AiService {
  static const String defaultTemplate = r'''
你是一位兼具严谨与表达能力的老师。我会给你一批用户记下来、但还没吃透的词或概念。

对每一个词，请依次输出下面四项：

1. definition —— 专业定义。
   * 必须先用严谨、准确的专业表述说清它是什么，可以写得完整、展开，不要为了短而牺牲准确性。
   * 涉及数学、统计、机器学习、物理、工程等定量内容时，必须给出关键公式。
     行内公式用 $...$ 包裹，独立成行的公式用 $$...$$ 包裹（Obsidian 可直接渲染）。
     公式里的符号要紧接着说明每个符号的含义。
   * 需要时可以补充定义成立的前提条件、与其他概念的形式化关系。
   * 这一栏允许详细，是四段里唯一可以写长的，通常 100-300 字，以讲透为准。

2. analogy —— 通俗解释。
   * 一两句话点破直觉，打一个比方就够，不要展开铺陈、不要复述定义。
   * 不要用术语解释术语。
   * 必须简短，通常 30-80 字，宁短勿长。

3. example —— 具体例子。
   * 一个小例子就够，能带数字就带数字，不要写成长篇推导。
   * 简短，通常 50-120 字；如需公式，用 $...$ / $$...$$。

4. extension —— 延伸关联。
   * 3-6 个值得继续查的相关概念、定理、方法或关键词，用顿号分隔。

其他要求：
- 简体中文；专业术语可括注英文原文。
- 数学公式一律用 LaTeX，不要用图片或纯文本凑合。
- 严格只输出一个 JSON 数组，不要任何解释性文字，不要 markdown 代码围栏。

这批词是：
{{TERMS}}

输出格式：
[{"term":"词","definition":"...","analogy":"...","example":"...","extension":"..."}]
''';

  static String buildPrompt(String template, List<Term> terms) {
    final buf = StringBuffer();
    for (final t in terms) {
      if (t.context != null && t.context!.trim().isNotEmpty) {
        buf.writeln('- ${t.name}（语境：${t.context!.trim()}）');
      } else {
        buf.writeln('- ${t.name}');
      }
    }
    final tpl = template.trim().isEmpty ? defaultTemplate : template;
    return tpl.replaceAll('{{TERMS}}', buf.toString().trimRight());
  }

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 120),
  ));

  static String _normalizeBase(String base) {
    var b = base.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (b.endsWith('/chat/completions')) return b;
    if (b.endsWith('/v1')) return '$b/chat/completions';
    return '$b/v1/chat/completions';
  }

  static Future<bool> testConnection(AiConfig cfg) async {
    final res = await _chat(cfg, [
      {'role': 'user', 'content': '回复两个字：正常'}
    ]);
    return res != null;
  }

  static Future<String?> _chat(AiConfig cfg, List<Map<String, String>> messages) async {
    try {
      final resp = await _dio.post(
        _normalizeBase(cfg.baseUrl),
        data: {
          'model': cfg.model,
          'messages': messages,
          'temperature': 0.4,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer ${cfg.apiKey}',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.plain,
        ),
      );
      final body = resp.data?.toString() ?? '';
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['choices'] is List) {
        final choices = decoded['choices'] as List;
        if (choices.isEmpty) return null;
        final msg = choices.first['message'];
        if (msg is Map && msg['content'] != null) return msg['content'].toString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 批量解释。返回解析成功的条目；失败抛出异常。
  static Future<List<ExplainedTerm>> explain(
    AiConfig cfg,
    List<Term> terms, {
    String? template,
  }) async {
    final prompt = buildPrompt(template ?? defaultTemplate, terms);
    final raw = await _chat(cfg, [
      {'role': 'user', 'content': prompt}
    ]);
    if (raw == null) {
      throw Exception('调用失败：请检查 BaseURL、Key 和模型名是否正确');
    }
    return parseExplanations(raw);
  }

  static List<ExplainedTerm> parseExplanations(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      final start = text.indexOf('\n');
      var end = text.lastIndexOf('```');
      if (start > 0 && end > start) {
        text = text.substring(start + 1, end).trim();
      } else {
        text = text.replaceAll('```', '').trim();
      }
    }
    final s = text.indexOf('[');
    final e = text.lastIndexOf(']');
    if (s < 0 || e <= s) {
      throw Exception('模型返回的不是 JSON 数组，无法解析');
    }
    final list = jsonDecode(text.substring(s, e + 1));
    if (list is! List) {
      throw Exception('模型返回的不是 JSON 数组，无法解析');
    }
    return list.map((item) {
      final m = item as Map<String, dynamic>;
      String pick(String k) => (m[k] ?? '').toString().trim();
      return ExplainedTerm(
        term: pick('term'),
        definition: pick('definition'),
        analogy: pick('analogy'),
        example: pick('example'),
        extension: pick('extension'),
      );
    }).where((x) => x.term.isNotEmpty).toList();
  }
}
