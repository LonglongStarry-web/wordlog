import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  Map<int, int> _counts = {};
  int _total = 0;
  int _thisMonth = 0;
  int _explained = 0;
  List<(String, int)> _topTags = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(const Duration(days: 7 * 16));
    final end = today.add(const Duration(days: 1));
    final counts = await db.dailyCounts(start, end);
    final total = await db.countBetween(DateTime(2000), end);
    final monthStart = DateTime(now.year, now.month, 1);
    final thisMonth = await db.countBetween(monthStart, end);

    final all = await db.allTerms();
    final explained = all.where((t) => t.isExplained).length;
    final tagCount = <String, int>{};
    for (final t in all) {
      for (final g in t.tags) {
        tagCount[g] = (tagCount[g] ?? 0) + 1;
      }
    }
    final top = tagCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (!mounted) return;
    setState(() {
      _counts = counts;
      _total = total;
      _thisMonth = thisMonth;
      _explained = explained;
      _topTags = top.take(8).map((e) => (e.key, e.value)).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('统计'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      _StatBox(label: '累计记词', value: '$_total'),
                      const SizedBox(width: 10),
                      _StatBox(label: '本月', value: '$_thisMonth'),
                      const SizedBox(width: 10),
                      _StatBox(label: '已解释', value: '$_explained'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text('最近 16 周',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  _Heatmap(counts: _counts),
                  const SizedBox(height: 8),
                  _Legend(),
                  if (_topTags.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Text('标签分布',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _topTags
                          .map((e) => Chip(
                                label: Text('${e.$1} · ${e.$2}'),
                                backgroundColor: const Color(0xFFF0F2FA),
                                side: BorderSide.none,
                                labelStyle: const TextStyle(fontSize: 12),
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;

  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF6B7280))),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heatmap extends StatelessWidget {
  final Map<int, int> counts;

  const _Heatmap({required this.counts});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 把今天所在这一周补齐到周日，作为最后一列
    final end = today.add(Duration(days: 7 - today.weekday));
    final cols = <Widget>[];
    for (var w = 15; w >= 0; w--) {
      final weekStart = end.subtract(Duration(days: 7 * w));
      final col = <Widget>[];
      for (var d = 0; d < 7; d++) {
        final day = weekStart.add(Duration(days: d));
        final key = day.year * 10000 + day.month * 100 + day.day;
        final c = counts[key] ?? 0;
        final future = day.isAfter(today);
        col.add(Padding(
          padding: const EdgeInsets.all(2),
          child: Container(
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              color: future
                  ? Colors.transparent
                  : _colorFor(c),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                  color: const Color(0xFFE7E9EF), width: future ? 0 : 0.6),
            ),
          ),
        ));
      }
      cols.add(Column(children: col));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: cols),
        ),
      ),
    );
  }

  static Color _colorFor(int c) {
    if (c <= 0) return const Color(0xFFF1F2F7);
    if (c == 1) return const Color(0xFFC9D3FB);
    if (c == 2) return const Color(0xFF9CAEF8);
    if (c <= 4) return const Color(0xFF6C86F2);
    return const Color(0xFF4C6EF5);
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Text('少', style: TextStyle(fontSize: 11, color: Color(0xFF9AA0AE))),
        SizedBox(width: 4),
        _Swatch(Color(0xFFF1F2F7)),
        _Swatch(Color(0xFFC9D3FB)),
        _Swatch(Color(0xFF9CAEF8)),
        _Swatch(Color(0xFF6C86F2)),
        _Swatch(Color(0xFF4C6EF5)),
        SizedBox(width: 4),
        Text('多', style: TextStyle(fontSize: 11, color: Color(0xFF9AA0AE))),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  const _Swatch(this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(width: 11, height: 11, color: color),
    );
  }
}
