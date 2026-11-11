import 'package:sqflite/sqflite.dart';

import '../models/note.dart';
import '../models/term.dart';

class AppDatabase {
  final Database db;

  AppDatabase._(this.db);

  static Future<AppDatabase> open() async {
    // 用 sqflite 自带的数据库目录，避免引入 path_provider -> jni -> CMake 依赖链
    final dir = await getDatabasesPath();
    final path = '$dir/wordlog.db';
    final db = await openDatabase(
      path,
      version: 3,
      onUpgrade: (d, oldV, newV) async {
        if (oldV < 2) {
          await d.execute('''
            CREATE TABLE IF NOT EXISTS notes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              term_id INTEGER NOT NULL,
              content TEXT NOT NULL DEFAULT '',
              images TEXT NOT NULL DEFAULT '[]',
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await d.execute(
              'CREATE INDEX IF NOT EXISTS idx_notes_term ON notes(term_id)');
        }
        if (oldV < 3) {
          // 默认模板更新过（通俗解释/例子改短）。只要点过「保存」旧模板就会被
          // 固化在设置表里，这里重置一次让新模板生效。
          await d.delete('settings',
              where: 'key = ?', whereArgs: ['prompt_template']);
          await d.insert(
            'settings',
            {'key': 'tpl_version', 'value': '3'},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      },
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE terms (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            context TEXT,
            created_at INTEGER NOT NULL,
            status INTEGER NOT NULL DEFAULT 0,
            definition TEXT,
            analogy TEXT,
            example TEXT,
            extension TEXT,
            model TEXT,
            explained_at INTEGER
          )
        ''');
        await d.execute('''
          CREATE TABLE tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            color INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await d.execute('''
          CREATE TABLE term_tags (
            term_id INTEGER NOT NULL,
            tag_id INTEGER NOT NULL,
            PRIMARY KEY (term_id, tag_id)
          )
        ''');
        await d.execute('''
          CREATE TABLE reviews (
            term_id INTEGER PRIMARY KEY,
            ease REAL NOT NULL DEFAULT 2.5,
            interval_days INTEGER NOT NULL DEFAULT 0,
            reps INTEGER NOT NULL DEFAULT 0,
            due_at INTEGER NOT NULL
          )
        ''');
        await d.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
        await d.execute('''
          CREATE TABLE notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            term_id INTEGER NOT NULL,
            content TEXT NOT NULL DEFAULT '',
            images TEXT NOT NULL DEFAULT '[]',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await d.execute('CREATE INDEX idx_terms_created ON terms(created_at)');
        await d.execute('CREATE INDEX idx_notes_term ON notes(term_id)');
      },
    );
    return AppDatabase._(db);
  }

  // ---------- terms ----------

  Future<int> insertTerm(Term t) async {
    final id = await db.insert('terms', t.toMap()..remove('id'));
    await _setTags(id, t.tags);
    return id;
  }

  Future<void> updateTerm(Term t) async {
    if (t.id == null) return;
    await db.update('terms', t.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [t.id]);
    await _setTags(t.id!, t.tags);
  }

  Future<void> deleteTerm(int id) async {
    await db.delete('term_tags', where: 'term_id = ?', whereArgs: [id]);
    await db.delete('reviews', where: 'term_id = ?', whereArgs: [id]);
    await db.delete('terms', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Term>> _hydrate(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r['id'] as int).toList();
    final q = List.filled(ids.length, '?').join(',');
    final tagRows = await db.rawQuery('''
      SELECT tt.term_id, t.name FROM term_tags tt
      JOIN tags t ON t.id = tt.tag_id
      WHERE tt.term_id IN ($q)
    ''', ids);
    final map = <int, List<String>>{};
    for (final r in tagRows) {
      map.putIfAbsent(r['term_id'] as int, () => []).add(r['name'] as String);
    }
    return rows
        .map((r) => Term.fromRow(r, tags: map[r['id'] as int] ?? const []))
        .toList();
  }

  Future<List<Term>> termsBetween(DateTime start, DateTime end) async {
    final rows = await db.query(
      'terms',
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'created_at DESC',
    );
    return _hydrate(rows);
  }

  Future<List<Term>> termsByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final q = List.filled(ids.length, '?').join(',');
    final rows = await db.query('terms', where: 'id IN ($q)', whereArgs: ids);
    return _hydrate(rows);
  }

  Future<List<Term>> allTerms() async {
    final rows = await db.query('terms', orderBy: 'created_at DESC');
    return _hydrate(rows);
  }

  Future<List<Term>> search(String keyword) async {
    final kw = '%$keyword%';
    final rows = await db.query(
      'terms',
      where: 'name LIKE ? OR context LIKE ? OR definition LIKE ?',
      whereArgs: [kw, kw, kw],
      orderBy: 'created_at DESC',
    );
    return _hydrate(rows);
  }

  Future<List<Term>> termsWithTag(String tag) async {
    final rows = await db.rawQuery('''
      SELECT tm.* FROM terms tm
      JOIN term_tags tt ON tt.term_id = tm.id
      JOIN tags t ON t.id = tt.tag_id
      WHERE t.name = ?
      ORDER BY tm.created_at DESC
    ''', [tag]);
    return _hydrate(rows);
  }

  Future<int> countBetween(DateTime start, DateTime end) async {
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM terms WHERE created_at >= ? AND created_at < ?',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<Map<int, int>> dailyCounts(DateTime start, DateTime end) async {
    final rows = await db.rawQuery(
      'SELECT created_at FROM terms WHERE created_at >= ? AND created_at < ?',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    final out = <int, int>{};
    for (final r in rows) {
      final dt = DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int);
      final key = dt.year * 10000 + dt.month * 100 + dt.day;
      out[key] = (out[key] ?? 0) + 1;
    }
    return out;
  }

  // ---------- notes ----------

  Future<int> insertNote(Note n) async {
    return db.insert('notes', n.toMap()..remove('id'));
  }

  Future<void> updateNote(Note n) async {
    if (n.id == null) return;
    await db.update('notes', n.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [n.id]);
  }

  Future<void> deleteNote(int id) async {
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Note>> notesFor(int termId) async {
    final rows = await db.query('notes',
        where: 'term_id = ?', whereArgs: [termId], orderBy: 'created_at DESC');
    return rows.map(Note.fromRow).toList();
  }

  Future<Map<int, int>> noteCounts() async {
    final rows = await db
        .rawQuery('SELECT term_id, COUNT(*) AS c FROM notes GROUP BY term_id');
    return {for (final r in rows) r['term_id'] as int: (r['c'] as int?) ?? 0};
  }

  /// 删除词条时清理它下面的笔记
  Future<void> deleteNotesOf(int termId) =>
      db.delete('notes', where: 'term_id = ?', whereArgs: [termId]);

  // ---------- 历史浏览 ----------

  /// 有记录的所有日期（yyyyMMdd 整数键 -> 当天词条数），按日期倒序。
  /// 用 SQLite 的 localtime 折算，保证按本地时区分天（否则会在 08:00 断开）。
  Future<List<(int, int)>> activeDays() async {
    final rows = await db.rawQuery('''
      SELECT date(created_at / 1000, 'unixepoch', 'localtime') AS d,
             COUNT(*) AS c
      FROM terms
      GROUP BY d
      ORDER BY d DESC
    ''');
    final out = <(int, int)>[];
    for (final r in rows) {
      final d = (r['d'] as String?) ?? '';
      final parts = d.split('-');
      if (parts.length != 3) continue;
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final dd = int.tryParse(parts[2]);
      if (y == null || m == null || dd == null) continue;
      out.add((y * 10000 + m * 100 + dd, (r['c'] as int?) ?? 0));
    }
    return out;
  }

  // ---------- tags ----------

  Future<void> _setTags(int termId, List<String> tags) async {
    await db.delete('term_tags', where: 'term_id = ?', whereArgs: [termId]);
    for (final t in tags) {
      final name = t.trim();
      if (name.isEmpty) continue;
      final existing =
          await db.query('tags', where: 'name = ?', whereArgs: [name]);
      int tagId;
      if (existing.isEmpty) {
        tagId = await db.insert('tags', {'name': name, 'color': 0});
      } else {
        tagId = existing.first['id'] as int;
      }
      await db.insert(
          'term_tags', {'term_id': termId, 'tag_id': tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<List<String>> allTags() async {
    final rows = await db.query('tags', orderBy: 'name');
    return rows.map((r) => r['name'] as String).toList();
  }

  // ---------- reviews ----------

  Future<void> upsertReview(ReviewState r) async {
    await db.insert(
      'reviews',
      {
        'term_id': r.termId,
        'ease': r.ease,
        'interval_days': r.intervalDays,
        'reps': r.reps,
        'due_at': r.dueAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Term>> dueReviews(DateTime now) async {
    final rows = await db.rawQuery('''
      SELECT tm.* FROM terms tm
      JOIN reviews rv ON rv.term_id = tm.id
      WHERE rv.due_at <= ? AND tm.status = 1
      ORDER BY rv.due_at ASC
    ''', [now.millisecondsSinceEpoch]);
    return _hydrate(rows);
  }

  Future<int> dueReviewCount(DateTime now) async {
    final r = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM reviews rv
      JOIN terms tm ON tm.id = rv.term_id
      WHERE rv.due_at <= ? AND tm.status = 1
    ''', [now.millisecondsSinceEpoch]);
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> scheduleReview(int termId, DateTime due, double ease, int intervalDays, int reps) async {
    await upsertReview(ReviewState(
      termId: termId,
      ease: ease,
      intervalDays: intervalDays,
      reps: reps,
      dueAt: due,
    ));
  }

  // ---------- settings ----------

  Future<String?> getSetting(String key) async {
    final rows =
        await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, String>> allSettings() async {
    final rows = await db.query('settings');
    return {
      for (final r in rows) r['key'] as String: (r['value'] as String?) ?? ''
    };
  }
}
