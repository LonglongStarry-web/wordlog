class Term {
  final int? id;
  final String name;
  final String? context;
  final DateTime createdAt;
  final int status; // 0 待解释 / 1 已解释
  final String? definition;
  final String? analogy;
  final String? example;
  final String? extension;
  final String? model;
  final DateTime? explainedAt;
  final List<String> tags;

  const Term({
    this.id,
    required this.name,
    this.context,
    required this.createdAt,
    this.status = 0,
    this.definition,
    this.analogy,
    this.example,
    this.extension,
    this.model,
    this.explainedAt,
    this.tags = const [],
  });

  bool get isExplained => status == 1;

  Term copyWith({
    int? id,
    String? name,
    String? context,
    DateTime? createdAt,
    int? status,
    String? definition,
    String? analogy,
    String? example,
    String? extension,
    String? model,
    DateTime? explainedAt,
    List<String>? tags,
  }) {
    return Term(
      id: id ?? this.id,
      name: name ?? this.name,
      context: context ?? this.context,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      definition: definition ?? this.definition,
      analogy: analogy ?? this.analogy,
      example: example ?? this.example,
      extension: extension ?? this.extension,
      model: model ?? this.model,
      explainedAt: explainedAt ?? this.explainedAt,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'context': context,
      'created_at': createdAt.millisecondsSinceEpoch,
      'status': status,
      'definition': definition,
      'analogy': analogy,
      'example': example,
      'extension': extension,
      'model': model,
      'explained_at': explainedAt?.millisecondsSinceEpoch,
    };
  }

  static Term fromRow(Map<String, dynamic> row, {List<String> tags = const []}) {
    return Term(
      id: row['id'] as int?,
      name: row['name'] as String,
      context: row['context'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      status: (row['status'] as int?) ?? 0,
      definition: row['definition'] as String?,
      analogy: row['analogy'] as String?,
      example: row['example'] as String?,
      extension: row['extension'] as String?,
      model: row['model'] as String?,
      explainedAt: row['explained_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['explained_at'] as int),
      tags: tags,
    );
  }
}

class ReviewState {
  final int termId;
  final double ease;
  final int intervalDays;
  final int reps;
  final DateTime dueAt;

  const ReviewState({
    required this.termId,
    required this.ease,
    required this.intervalDays,
    required this.reps,
    required this.dueAt,
  });
}
