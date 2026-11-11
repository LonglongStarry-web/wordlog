import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../main.dart';
import '../models/term.dart';
import '../services/ai_service.dart';

class BatchScreen extends ConsumerStatefulWidget {
  final List<Term> terms;

  const BatchScreen({super.key, required this.terms});

  @override
  ConsumerState<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends ConsumerState<BatchScreen> {
  bool _running = false;
  String? _error;
  String _status = '';

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _status = '正在请求大模型…';
    });

    final settings = ref.read(settingsProvider);
    final cfg = await settings.loadConfig();
    if (!cfg.ready) {
      setState(() {
        _running = false;
        _error = '还没配置大模型：请到「设置」里填 BaseURL、Key 和模型名';
      });
      return;
    }
    final tpl = await settings.template();

    try {
      // 已经解释过的不再重复消耗
      final targets = widget.terms.where((t) => !t.isExplained).toList();
      if (targets.isEmpty) {
        setState(() {
          _running = false;
          _status = '选中的词都已经解释过了';
        });
        return;
      }

      final results = await AiService.explain(cfg, targets, template: tpl);
      final db = ref.read(dbProvider);
      final byName = {for (final r in results) r.term.trim(): r};

      for (final t in targets) {
        final r = byName[t.name.trim()];
        if (r == null) {
          // 模型可能改写了词名，退而求其次按包含匹配
          final alt = results.firstWhere(
            (x) => t.name.contains(x.term.trim()) || x.term.trim().contains(t.name),
            orElse: () => ExplainedTerm(
                term: t.name,
                definition: '',
                analogy: '',
                example: '',
                extension: ''),
          );
          await _save(db, t, alt, cfg.model);
        } else {
          await _save(db, t, r, cfg.model);
        }
      }

      ref.read(revisionProvider.notifier).bump();
      if (!mounted) return;
      setState(() {
        _running = false;
        _status = '完成，共解释 ${targets.length} 个词';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _save(
      AppDatabase db, Term t, ExplainedTerm r, String model) async {
    final updated = t.copyWith(
      status: r.definition.isEmpty ? t.status : 1,
      definition: r.definition.isEmpty ? t.definition : r.definition,
      analogy: r.analogy.isEmpty ? t.analogy : r.analogy,
      example: r.example.isEmpty ? t.example : r.example,
      extension: r.extension.isEmpty ? t.extension : r.extension,
      model: r.definition.isEmpty ? t.model : model,
      explainedAt: r.definition.isEmpty ? t.explainedAt : DateTime.now(),
    );
    await db.updateTerm(updated);
    if (updated.isExplained && t.id != null) {
      await db.scheduleReview(
        t.id!,
        DateTime.now().add(const Duration(hours: 8)),
        2.5,
        0,
        0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('批量解释')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('本次将解释 ${widget.terms.length} 个词',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.terms
                          .map((t) => Chip(
                                label: Text(t.name),
                                backgroundColor: const Color(0xFFF0F2FA),
                                side: BorderSide.none,
                                labelStyle: const TextStyle(fontSize: 12),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (_running) const LinearProgressIndicator(),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_status),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDECEC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!,
                    style: const TextStyle(color: Color(0xFFA32D2D))),
              ),
            ],
            const Spacer(),
            FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.auto_awesome),
              label: Text(_running ? '生成中…' : '开始解释'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}
