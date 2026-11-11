import 'dart:convert';

/// 词条下随手记的笔记：一段文本 + 若干图片（存的是本地绝对路径）
class Note {
  final int? id;
  final int termId;
  final String content;
  final List<String> images;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Note({
    this.id,
    required this.termId,
    this.content = '',
    this.images = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  Note copyWith({
    int? id,
    int? termId,
    String? content,
    List<String>? images,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      termId: termId ?? this.termId,
      content: content ?? this.content,
      images: images ?? this.images,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'term_id': termId,
      'content': content,
      'images': jsonEncode(images),
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  static Note fromRow(Map<String, dynamic> row) {
    List<String> imgs;
    final raw = row['images'];
    try {
      final decoded = raw == null ? <dynamic>[] : jsonDecode(raw as String);
      imgs = (decoded as List).map((e) => e.toString()).toList();
    } catch (_) {
      imgs = const [];
    }
    return Note(
      id: row['id'] as int?,
      termId: row['term_id'] as int,
      content: (row['content'] as String?) ?? '',
      images: imgs,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }
}
