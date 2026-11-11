import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';
import '../models/term.dart';
import '../widgets/rich_content.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  List<Term> _queue = [];
  bool _loading = true;
  bool _flipped = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final list = await db.dueReviews(DateTime.now());
    if (!mounted) return;
    setState(() {
      _queue = list;
      _loading = false;
      _flipped = false;
    });
  }

  Future<void> _grade(bool known) async {
    if (_queue.isEmpty) return;
    final db = ref.read(dbProvider);
    final t = _queue.first;
    if (t.id == null) return;

    // 简化版 SM-2
    double ease = 2.5;
    int interval = 0;
    int reps = 0;
    final existing = await db.db.rawQuery(
        'SELECT ease, interval_days, reps FROM reviews WHERE term_id = ?',
        [t.id]);
    if (existing.isNotEmpty) {
      ease = (existing.first['ease'] as num).toDouble();
      interval = (existing.first['interval_days'] as num).toInt();
      reps = (existing.first['reps'] as num).toInt();
    }

    if (!known) {
      reps = 0;
      interval = 1;
      ease = (ease - 0.2).clamp(1.3, 2.8);
    } else {
      reps += 1;
      if (reps == 1) {
        interval = 1;
      } else if (reps == 2) {
        interval = 3;
      } else {
        interval = (interval * ease).round();
        if (interval < 1) interval = 1;
      }
      ease = (ease + 0.1).clamp(1.3, 2.8);
    }

    await db.scheduleReview(
      t.id!,
      DateTime.now().add(Duration(days: interval)),
      ease,
      interval,
      reps,
    );

    if (!mounted) return;
    setState(() {
      _queue = _queue.sublist(1);
      _flipped = false;
    });
    ref.read(revisionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('复习'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _queue.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 44, color: Color(0xFFB9BECB)),
                        SizedBox(height: 12),
                        Text('今天的复习都完成了',
                            style: TextStyle(color: Color(0xFF6B7280))),
                        SizedBox(height: 6),
                        Text(
                          '新解释的词会在 8 小时后进入复习队列',
                          style: TextStyle(
                              color: Color(0xFF9AA0AE), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '待复习 ${_queue.length} 个',
                          style: const TextStyle(
                              color: Color(0xFF6B7280), fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _flipped = !_flipped),
                          child: Card(
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              child: _flipped ? _back() : _front(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _grade(false),
                              icon: const Icon(Icons.refresh),
                              label: const Text('还模糊'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _grade(true),
                              icon: const Icon(Icons.check),
                              label: const Text('懂了'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _front() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _queue.first.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 26, fontWeight: FontWeight.w600, color: Color(0xFF1F2430)),
        ),
        const SizedBox(height: 18),
        const Text('点击翻面看解释',
            style: TextStyle(color: Color(0xFF9AA0AE), fontSize: 13)),
      ],
    );
  }

  Widget _back() {
    final t = _queue.first;
    final rows = <(String, String?)>[
      ('定义', t.definition),
      ('类比', t.analogy),
      ('例子', t.example),
      ('延伸', t.extension),
    ];
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.name,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF1F2430)),
          ),
          const SizedBox(height: 14),
          ...rows.where((r) => (r.$2 ?? '').trim().isNotEmpty).map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.$1,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4C6EF5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      RichContent(
                        text: r.$2!.trim(),
                        fontSize: 15,
                        height: 1.55,
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
