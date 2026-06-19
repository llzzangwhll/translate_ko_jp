import 'package:sqflite/sqflite.dart';

import '../../core/language.dart';
import '../../domain/entities/language_direction.dart';
import '../../domain/entities/translation_result.dart';
import 'history_store.dart';

class SqfliteHistoryStore implements HistoryStore {
  static const String tableName = 'translations';
  static const int _schemaVersion = 1;

  Database? _db;

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('SqfliteHistoryStore.open() must be called first');
    }
    return db;
  }

  Future<void> open({required String path}) async {
    _db = await openDatabase(
      path,
      version: _schemaVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_text TEXT NOT NULL,
            translated_text TEXT NOT NULL,
            source_lang TEXT NOT NULL,
            target_lang TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  @override
  Future<int> insert(TranslationResult result) {
    return _database.insert(tableName, _toRow(result));
  }

  @override
  Future<List<TranslationResult>> getAll() async {
    final rows = await _database.query(
      tableName,
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> delete(int id) async {
    await _database.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> clear() async {
    await _database.delete(tableName);
  }

  Map<String, Object?> _toRow(TranslationResult r) {
    return <String, Object?>{
      if (r.id != null) 'id': r.id,
      'source_text': r.sourceText,
      'translated_text': r.translatedText,
      'source_lang': r.direction.from.name,
      'target_lang': r.direction.to.name,
      'created_at': r.createdAt.millisecondsSinceEpoch,
    };
  }

  TranslationResult _fromRow(Map<String, Object?> row) {
    return TranslationResult(
      id: row['id'] as int?,
      sourceText: row['source_text'] as String,
      translatedText: row['translated_text'] as String,
      direction: LanguageDirection(
        from: _langFromName(row['source_lang'] as String),
        to: _langFromName(row['target_lang'] as String),
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }

  Language _langFromName(String name) {
    return Language.values.firstWhere((l) => l.name == name);
  }
}
