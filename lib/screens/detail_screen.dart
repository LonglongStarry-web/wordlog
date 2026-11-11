import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/note.dart';
import '../models/term.dart';
import '../services/ai_service.dart';
import '../services/export_service.dart';
import '../services/image_store.dart';
import '../widgets/rich_content.dart';

class DetailScreen extends ConsumerStatefulWidget {
  final Term term;

  const DetailScreen({super.key, required this.term});

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  late Term _t;
  bool _busy = false;
  List<Note> _notes = [];
  bool _loadingNotes = true;

  @override
  void initState() {
    super.initState();
    _t = widget.term;
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    if (_t.id == null) return;
    final list = await ref.read(dbProvider).notesFor(_t.id!);
    if (!mounted) return;
    setState(() {
      _notes = list;
      _loadingNotes = false;
    });
  }

  Future<void> _reExplain() async {
    setState(() => _busy = true);
    final settings = ref.read(settingsProvider);
    final cfg = await settings.loadConfig();
    if (!cfg.ready) {
      setState(() => _busy = false);
      _snack('请先在设置里配置大模型');
      return;
    }
    final tpl = await settings.template();
    try {
      final res = await AiService.explain(cfg, [_t], template: tpl);
      final r = res.firstWhere(
        (x) => x.term.trim() == _t.name.trim(),
        orElse: () => res.first,
      );
      final updated = _t.copyWith(
        status: 1,
        definition: r.definition,
        analogy: r.analogy,
        example: r.example,
        extension: r.extension,
        model: cfg.model,
        explainedAt: DateTime.now(),
      );
      await ref.read(dbProvider).updateTerm(updated);
      if (_t.id != null) {
        await ref.read(dbProvider).scheduleReview(
              _t.id!,
              DateTime.now().add(const Duration(hours: 8)),
              2.5,
              0,
              0,
            );
      }
      setState(() => _t = updated);
      ref.read(revisionProvider.notifier).bump();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _editTags() async {
    final ctrl = TextEditingController(text: _t.tags.join(', '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('编辑标签'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '逗号分隔'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    final tags = ctrl.text
        .split(RegExp(r'[,，\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final updated = _t.copyWith(tags: tags);
    await ref.read(dbProvider).updateTerm(updated);
    setState(() => _t = updated);
    ref.read(revisionProvider.notifier).bump();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除这个词？'),
        content: const Text('连同它下面的笔记一起删除，无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    if (_t.id != null) {
      for (final n in _notes) {
        for (final img in n.images) {
          await ImageStore.deleteFile(img);
        }
      }
      await ref.read(dbProvider).deleteNotesOf(_t.id!);
      await ref.read(dbProvider).deleteTerm(_t.id!);
    }
    ref.read(revisionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _openNoteEditor({Note? existing}) async {
    if (_t.id == null) return;
    final contentCtrl = TextEditingController(text: existing?.content ?? '');
    final images = <String>[...(existing?.images ?? const <String>[])];
    final editing = existing != null;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  editing ? '编辑笔记' : '写点自己的理解',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: contentCtrl,
                  autofocus: !editing,
                  maxLines: 6,
                  minLines: 3,
                  decoration: const InputDecoration(
                    hintText: '想到什么写什么，不用组织语言',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                if (images.isNotEmpty)
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: images.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 8),
                      itemBuilder: (context, i) => Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              File(images[i]),
                              width: 84,
                              height: 84,
                              fit: BoxFit.cover,
                              errorBuilder: (c, e, s) => Container(
                                width: 84,
                                height: 84,
                                color: const Color(0xFFF1F2F7),
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: GestureDetector(
                              onTap: () => setLocal(() => images.removeAt(i)),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close,
                                    size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final p =
                            await ImageStore.pickAndSave(ImageSource.gallery);
                        if (p != null) setLocal(() => images.add(p));
                      },
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('相册'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final p =
                            await ImageStore.pickAndSave(ImageSource.camera);
                        if (p != null) setLocal(() => images.add(p));
                      },
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('拍照'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved != true) return;

    final now = DateTime.now();
    final text = contentCtrl.text.trim();
    if (text.isEmpty && images.isEmpty) return;

    if (existing != null && existing.id != null) {
      await ref.read(dbProvider).updateNote(existing.copyWith(
            content: text,
            images: images,
            updatedAt: now,
          ));
    } else {
      await ref.read(dbProvider).insertNote(Note(
            termId: _t.id!,
            content: text,
            images: images,
            createdAt: now,
            updatedAt: now,
          ));
    }
    await _loadNotes();
    ref.read(revisionProvider.notifier).bump();
  }

  Future<void> _deleteNote(Note n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除这条笔记？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || n.id == null) return;
    for (final img in n.images) {
      await ImageStore.deleteFile(img);
    }
    await ref.read(dbProvider).deleteNote(n.id!);
    await _loadNotes();
    ref.read(revisionProvider.notifier).bump();
  }

  void _viewImage(String path) {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(child: InteractiveViewer(child: Image.file(File(path)))),
            Positioned(
              right: 8,
              top: 24,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(c),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocks = <(String, String?)>[
      ('专业定义', _t.definition),
      ('通俗解释', _t.analogy),
      ('例子', _t.example),
      ('延伸', _t.extension),
    ];
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_t.name),
          actions: [
            IconButton(
                onPressed: _editTags, icon: const Icon(Icons.label_outline)),
            IconButton(
                onPressed: _delete, icon: const Icon(Icons.delete_outline)),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: '解释'), Tab(text: 'Markdown')],
          ),
        ),
        body: TabBarView(
          children: [
            _explainTab(blocks),
            _markdownTab(),
          ],
        ),
      ),
    );
  }

  Widget _explainTab(List<(String, String?)> blocks) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (_t.context != null && _t.context!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '语境：${_t.context}',
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
            ),
          ),
        if (_t.tags.isNotEmpty)
          Wrap(
            spacing: 6,
            children: _t.tags
                .map((t) => Chip(
                      label: Text(t),
                      backgroundColor: const Color(0xFFF0F2FA),
                      side: BorderSide.none,
                      labelStyle: const TextStyle(fontSize: 12),
                    ))
                .toList(),
          ),
        const SizedBox(height: 12),
        if (!_t.isExplained)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('这个词还没解释'),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _reExplain,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(_busy ? '生成中…' : '让 AI 解释'),
                  ),
                ],
              ),
            ),
          )
        else
          ...blocks
              .where((r) => (r.$2 ?? '').trim().isNotEmpty)
              .map((r) => _ExplainBlock(label: r.$1, text: r.$2!.trim())),
        const SizedBox(height: 8),
        _buildNotesSection(),
        const SizedBox(height: 8),
        Text(
          '记录于 ${DateFormat('yyyy-MM-dd HH:mm').format(_t.createdAt)}'
          '${_t.model != null ? ' · ${_t.model}' : ''}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF9AA0AE)),
        ),
        if (_t.isExplained) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _reExplain,
            icon: const Icon(Icons.refresh),
            label: const Text('重新生成解释'),
          ),
        ],
      ],
    );
  }

  /// Markdown 原文：公式、列表都保持导出时的样子，可直接复制进 Obsidian 渲染
  Widget _markdownTab() {
    final tid = _t.id;
    final md = ExportService.buildMarkdown(
      [_t],
      title: '# ${_t.name}',
      notes: (tid != null && _notes.isNotEmpty) ? {tid: _notes} : null,
    );
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '和导出到 Obsidian 的内容一致，公式在这里显示为 LaTeX 原文，粘贴过去就能渲染。',
                style: TextStyle(fontSize: 12, color: Color(0xFF9AA0AE)),
              ),
              const SizedBox(height: 10),
              SelectableText(
                md,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  fontFamily: 'monospace',
                  color: Color(0xFF3D4453),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 20,
          child: FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: md));
              _snack('Markdown 已复制');
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('复制'),
          ),
        ),
      ],
    );
  }

  Widget _buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('我的笔记',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            if (_notes.isNotEmpty)
              Text('${_notes.length}',
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF9AA0AE))),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _openNoteEditor(),
              icon: const Icon(Icons.add),
              label: const Text('记一笔'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_loadingNotes)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_notes.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('还没记过自己的理解',
                      style: TextStyle(color: Color(0xFF6B7280))),
                  SizedBox(height: 4),
                  Text(
                    '看完解释后想到什么，随手记下来，可以加图',
                    style: TextStyle(color: Color(0xFF9AA0AE), fontSize: 12),
                  ),
                ],
              ),
            ),
          )
        else
          ..._notes.map((n) => _NoteCard(
                note: n,
                onTap: () => _openNoteEditor(existing: n),
                onDelete: () => _deleteNote(n),
                onImage: _viewImage,
              )),
      ],
    );
  }
}

class _ExplainBlock extends StatelessWidget {
  final String label;
  final String text;

  const _ExplainBlock({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF4C6EF5),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              RichContent(text: text, fontSize: 15),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<String> onImage;

  const _NoteCard({
    required this.note,
    required this.onTap,
    required this.onDelete,
    required this.onImage,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: const Color(0xFFFFFCF3),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('MM-dd HH:mm').format(note.createdAt),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF9AA0AE)),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: onDelete,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (note.content.trim().isNotEmpty)
                  RichContent(
                      text: note.content.trim(),
                      fontSize: 14,
                      height: 1.55),
                if (note.images.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: note.images
                        .map((p) => GestureDetector(
                              onTap: () => onImage(p),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(p),
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) => Container(
                                    width: 72,
                                    height: 72,
                                    color: const Color(0xFFF1F2F7),
                                    child: const Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
