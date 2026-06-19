import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:translate_ko_jp/core/language.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/data/services/sqflite_history_store.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqfliteHistoryStore store;

  setUp(() async {
    store = SqfliteHistoryStore();
    await store.open(path: inMemoryDatabasePath);
  });

  tearDown(() async {
    await store.close();
  });

  TranslationResult sample({
    String source = '안녕하세요',
    String translated = 'こんにちは',
    LanguageDirection? dir,
    DateTime? at,
  }) {
    return TranslationResult(
      sourceText: source,
      translatedText: translated,
      direction: dir ?? LanguageDirection.koToJa(),
      createdAt: at ?? DateTime.fromMillisecondsSinceEpoch(1000),
    );
  }

  test('insert returns a positive autoincrement id', () async {
    final id = await store.insert(sample());
    expect(id, greaterThan(0));
  });

  test('getAll round-trips fields and reconstructs direction', () async {
    await store.insert(sample(
      source: '안녕',
      translated: 'やあ',
      dir: LanguageDirection.koToJa(),
      at: DateTime.fromMillisecondsSinceEpoch(5000),
    ));

    final all = await store.getAll();

    expect(all, hasLength(1));
    final row = all.first;
    expect(row.id, isNotNull);
    expect(row.sourceText, '안녕');
    expect(row.translatedText, 'やあ');
    expect(row.direction.from, Language.ko);
    expect(row.direction.to, Language.ja);
    expect(row.createdAt, DateTime.fromMillisecondsSinceEpoch(5000));
  });

  test('getAll returns newest first (ORDER BY created_at DESC)', () async {
    await store.insert(sample(source: 'old', at: DateTime.fromMillisecondsSinceEpoch(1000)));
    await store.insert(sample(source: 'mid', at: DateTime.fromMillisecondsSinceEpoch(2000)));
    await store.insert(sample(source: 'new', at: DateTime.fromMillisecondsSinceEpoch(3000)));

    final all = await store.getAll();

    expect(all.map((r) => r.sourceText).toList(), ['new', 'mid', 'old']);
  });

  test('stores ja->ko direction and reconstructs it', () async {
    await store.insert(sample(dir: LanguageDirection.jaToKo()));
    final row = (await store.getAll()).first;
    expect(row.direction.from, Language.ja);
    expect(row.direction.to, Language.ko);
  });

  test('delete removes only the matching row', () async {
    final keepId = await store.insert(sample(source: 'keep'));
    final dropId = await store.insert(sample(source: 'drop'));

    await store.delete(dropId);

    final all = await store.getAll();
    expect(all, hasLength(1));
    expect(all.single.id, keepId);
    expect(all.single.sourceText, 'keep');
  });

  test('delete with unknown id is a no-op', () async {
    await store.insert(sample());
    await store.delete(999999);
    expect(await store.getAll(), hasLength(1));
  });

  test('clear removes all rows', () async {
    await store.insert(sample(source: 'a'));
    await store.insert(sample(source: 'b'));

    await store.clear();

    expect(await store.getAll(), isEmpty);
  });
}
