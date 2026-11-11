import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/term.dart';
import '../services/export_service.dart';
import '../widgets/rich_content.dart';
import 'detail_screen.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  Map<int, int> _noteCounts = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadNoteCounts() async {
    final m = await ref.read(dbProvider).noteCounts();
    if (!mounted) return;
    setState(() => _noteCounts = m);
  }

  @override
  Widget build(BuildContext context) {
    final kw = _searchCtrl.text;
    final asyncTerms =
        _searching ? ref.watch(searchProvider(kw)) : ref.watch(allTermsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_searching ? '搜索历史' : '历史'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _searchCtrl.clear();
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜词名、语境或解释',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          Expanded(
            child: asyncTerms.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('出错了：$e')),
              data: (terms) {
                if (_noteCounts.isEmpty && terms.isNotEmpty && !_searching) {
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _loadNoteCounts());
                }
                if (terms.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.history_toggle_off,
                              size: 44, color: Color(0xFFB9BECB)),
                          const SizedBox(height: 12),
                          Text(
                            _searching ? '没找到匹配的词' : '还没有历史记录',
                            style: const TextStyle(color: Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return _searching
                    ? _buildFlat(terms)
                    : _buildByDay(terms);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlat(List<Term> terms) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: terms.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) =>
          _TermRow(term: terms[i], noteCount: _noteCounts[terms[i].id] ?? 0),
    );
  }

  Widget _buildByDay(List<Term> terms) {
    final byDay = <String, List<Term>>{};
    for (final t in terms) {
      byDay.putIfAbsent(DateFormat('yyyy-MM-dd').format(t.createdAt), () => [])
        ..add(t);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: () async {
        ref.read(revisionProvider.notifier).bump();
        await _loadNoteCounts();
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: days.length,
        itemBuilder: (context, i) {
          final day = days[i];
          final list = byDay[day]!;
          return _DayGroup(
            day: day,
            terms: list,
            noteCounts: _noteCounts,
          );
        },
      ),
    );
  }
}

class _DayGroup extends StatelessWidget {
  final String day;
  final List<Term> terms;
  final Map<int, int> noteCounts;

  const _DayGroup({
    required this.day,
    required this.terms,
    required this.noteCounts,
  });

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(day);
    final wd = dt == null ? '' : ExportService.weekdayOf(dt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 15, color: Color(0xFF9AA0AE)),
                  const SizedBox(width: 6),
                  Text('$day $wd',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${terms.length} 个词',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF9AA0AE))),
                ],
              ),
              const SizedBox(height: 6),
              ...terms.map((t) => _TermRow(
                    term: t,
                    noteCount: noteCounts[t.id] ?? 0,
                    dense: true,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _TermRow extends StatelessWidget {
  final Term term;
  final int noteCount;
  final bool dense;

  const _TermRow({
    required this.term,
    required this.noteCount,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final raw = term.isExplained
        ? (term.definition ?? '')
        : (term.context?.isNotEmpty == true ? term.context! : '（待解释）');
    final summary = plainPreview(raw);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: dense,
      title: Text(term.name,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      subtitle: summary.trim().isEmpty
          ? null
          : Text(
              summary.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (noteCount > 0) ...[
            const Icon(Icons.notes_outlined, size: 15, color: Color(0xFFB7791F)),
            const SizedBox(width: 2),
            Text('$noteCount',
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFFB7791F))),
          ],
          if (!term.isExplained)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.help_outline, size: 15, color: Color(0xFFB7791F)),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFC4C8D2)),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DetailScreen(term: term)),
      ),
    );
  }
}
