import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/note.dart';
import '../models/term.dart';
import '../services/export_service.dart';
import '../services/image_store.dart';
import '../services/platform_service.dart';
import '../services/notify_service.dart';
import '../widgets/rich_content.dart';
import 'batch_screen.dart';
import 'detail_screen.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  final _nameCtrl = TextEditingController();
  final _ctxCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  bool _expanded = false;
  bool _searching = false;
  final Set<int> _selected = {};

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ctxCtrl.dispose();
    _tagCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final tags = _tagCtrl.text
        .split(RegExp(r'[,，\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final ctx = _ctxCtrl.text.trim();
    await ref.read(dbProvider).insertTerm(Term(
          name: name,
          context: ctx.isEmpty ? null : ctx,
          createdAt: DateTime.now(),
          tags: tags,
        ));
    _nameCtrl.clear();
    _ctxCtrl.clear();
    ref.read(revisionProvider.notifier).bump();
    if (!mounted) return;
    FocusScope.of(context).requestFocus(FocusNode());
  }

  Future<void> _delete(Term t) async {
    final id = t.id;
    if (id == null) return;
    final db = ref.read(dbProvider);
    // 连同笔记和笔记里的图片一起清掉，避免留下孤儿文件
    for (final n in await db.notesFor(id)) {
      for (final img in n.images) {
        await ImageStore.deleteFile(img);
      }
    }
    await db.deleteNotesOf(id);
    await db.deleteTerm(id);
    _selected.remove(id);
    ref.read(revisionProvider.notifier).bump();
  }

  Future<void> _export() async {
    final scope = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('导出范围', style: TextStyle(fontWeight: FontWeight.w600))),
            ListTile(
              leading: const Icon(Icons.today_outlined),
              title: const Text('仅今天'),
              onTap: () => Navigator.pop(c, 'today'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('本月（推荐）'),
              onTap: () => Navigator.pop(c, 'month'),
            ),
            ListTile(
              leading: const Icon(Icons.all_inclusive),
              title: const Text('全部'),
              onTap: () => Navigator.pop(c, 'all'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (scope == null) return;

    final db = ref.read(dbProvider);
    final now = DateTime.now();
    List<Term> terms;
    DateTime anchor;
    if (scope == 'today') {
      final s = DateTime(now.year, now.month, now.day);
      terms = await db.termsBetween(s, s.add(const Duration(days: 1)));
      anchor = s;
    } else if (scope == 'month') {
      final s = DateTime(now.year, now.month, 1);
      final e = DateTime(now.year, now.month + 1, 1);
      terms = await db.termsBetween(s, e);
      anchor = s;
    } else {
      terms = await db.allTerms();
      anchor = now;
    }
    if (terms.isEmpty) {
      if (mounted) _snack('这个范围内还没有记词');
      return;
    }

    final settings = ref.read(settingsProvider);
    var uri = await settings.exportUri();
    uri ??= await PlatformService.pickDirectory();
    if (uri == null || uri.isEmpty) {
      if (mounted) _snack('没有选择导出目录');
      return;
    }
    await settings.saveExportUri(uri);

    // 带上词条下的笔记（含图片）
    final notes = <int, List<Note>>{};
    for (final t in terms) {
      if (t.id == null) continue;
      final list = await db.notesFor(t.id!);
      if (list.isNotEmpty) notes[t.id!] = list;
    }

    final fileName = ExportService.monthFileName(anchor);
    final incoming = ExportService.buildMarkdown(
      terms,
      title: scope == 'all' ? '# 我的词记本' : '# ${DateFormat('yyyy-MM').format(anchor)}',
      notes: notes,
    );
    final existing = await PlatformService.readFile(uri, fileName) ?? '';
    final merged = ExportService.merge(existing, incoming);
    final ok = await PlatformService.writeFile(uri, fileName, merged);
    if (!mounted) return;
    if (!ok) {
      _snack('写入失败，请重新选择目录');
      return;
    }

    // 笔记图片一并写进导出目录下的 images/
    var imgCount = 0;
    for (final list in notes.values) {
      for (final n in list) {
        for (final img in n.images) {
          try {
            final bytes = await File(img).readAsBytes();
            final name = img.split(RegExp(r'[\\/]')).last;
            final wrote =
                await PlatformService.writeBytes(uri, 'images/$name', bytes);
            if (wrote) imgCount++;
          } catch (_) {}
        }
      }
    }

    await NotifyService.notifyExportDone(fileName);
    _snack(imgCount > 0
        ? '已写入 $fileName（含 $imgCount 张图）'
        : '已写入 $fileName');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openBatch(List<Term> terms) async {
    final picked = terms.where((t) => _selected.contains(t.id)).toList();
    if (picked.isEmpty) {
      _snack('先勾选要解释的词');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BatchScreen(terms: picked)),
    );
    if (!mounted) return;
    setState(() => _selected.clear());
    ref.read(revisionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context) {
    final kw = _searchCtrl.text;
    final asyncTerms = _searching
        ? ref.watch(searchProvider(kw))
        : ref.watch(todayTermsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_searching ? '搜索' : '今日'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _searchCtrl.clear();
            }),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: '导出 Markdown',
            onPressed: _export,
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
            )
          else
            _buildInput(),
          Expanded(
            child: asyncTerms.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('出错了：$e')),
              data: (terms) => terms.isEmpty
                  ? const _EmptyHint()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                      itemCount: terms.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (_, i) => _TermCard(
                        term: terms[i],
                        selected: _selected.contains(terms[i].id),
                        onToggle: (v) => setState(() {
                          final id = terms[i].id;
                          if (id == null) return;
                          if (v == true) {
                            _selected.add(id);
                          } else {
                            _selected.remove(id);
                          }
                        }),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => DetailScreen(term: terms[i])),
                        ).then((_) => ref.read(revisionProvider.notifier).bump()),
                        onDelete: () => _delete(terms[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                final list = (asyncTerms.value ?? []);
                _openBatch(list);
              },
              icon: const Icon(Icons.auto_awesome),
              label: Text('解释 ${_selected.length} 个'),
            ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: const InputDecoration(
                    hintText: '记一个词，回车即可',
                    prefixIcon: Icon(Icons.edit_note),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.expand_less : Icons.tune),
                tooltip: '选填语境和标签',
              ),
              const SizedBox(width: 4),
              FilledButton(onPressed: _add, child: const Text('记下')),
            ],
          ),
          if (_expanded) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _ctxCtrl,
              decoration: const InputDecoration(
                hintText: '语境（选填）：在哪看到的',
                prefixIcon: Icon(Icons.short_text),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tagCtrl,
              decoration: const InputDecoration(
                hintText: '标签（选填）：逗号分隔，如 工作, AI',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.notes_outlined, size: 44, color: Color(0xFFB9BECB)),
            SizedBox(height: 12),
            Text('今天还没有记词', style: TextStyle(color: Color(0xFF6B7280))),
            SizedBox(height: 6),
            Text(
              '遇到不懂的词，直接在上面敲进去就行\n晚上再让 AI 一次性讲清楚',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF9AA0AE), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _TermCard extends StatelessWidget {
  final Term term;
  final bool selected;
  final ValueChanged<bool?> onToggle;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _TermCard({
    required this.term,
    required this.selected,
    required this.onToggle,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(term.createdAt);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: selected, onChanged: onToggle),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            term.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2430),
                            ),
                          ),
                        ),
                        Text(time,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF9AA0AE))),
                      ],
                    ),
                    if (term.context != null && term.context!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        term.context!,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF6B7280)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (term.isExplained && term.definition != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        plainPreview(term.definition!),
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF3D4453)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (term.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: term.tags
                            .map((t) => Chip(
                                  label: Text(t),
                                  visualDensity: VisualDensity.compact,
                                  labelStyle: const TextStyle(fontSize: 12),
                                  backgroundColor: const Color(0xFFF0F2FA),
                                  side: BorderSide.none,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ))
                            .toList(),
                      ),
                    ],
                    if (!term.isExplained) ...[
                      const SizedBox(height: 6),
                      const Text(
                        '待解释',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFFB7791F)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
