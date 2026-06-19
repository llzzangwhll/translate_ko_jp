import 'package:flutter_test/flutter_test.dart';

import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/core/language.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/data/repositories/history_repository.dart';

import '../../fakes/fake_history_store.dart';

TranslationResult _sample({DateTime? at}) => TranslationResult(
      sourceText: '안녕',
      translatedText: 'やあ',
      direction: LanguageDirection.koToJa(),
      createdAt: at ?? DateTime.fromMillisecondsSinceEpoch(1000),
    );

void main() {
  late FakeHistoryStore store;
  late HistoryRepository repo;

  setUp(() {
    store = FakeHistoryStore();
    repo = HistoryRepositoryImpl(store);
  });

  group('save', () {
    test('returns Ok(id) on success', () async {
      final result = await repo.save(_sample());
      expect(result, isA<Ok<int>>());
      expect((result as Ok<int>).value, greaterThan(0));
    });

    test('maps store exception to Err(StorageFailure)', () async {
      store.throwOnInsert = true;
      final result = await repo.save(_sample());
      expect(result, isA<Err<int>>());
      expect((result as Err<int>).failure, isA<StorageFailure>());
    });
  });

  group('getAll', () {
    test('returns Ok(list) newest first', () async {
      await store.insert(_sample(at: DateTime.fromMillisecondsSinceEpoch(1000)));
      await store.insert(_sample(at: DateTime.fromMillisecondsSinceEpoch(2000)));

      final result = await repo.getAll();
      expect(result, isA<Ok<List<TranslationResult>>>());
      final list = (result as Ok<List<TranslationResult>>).value;
      expect(list, hasLength(2));
      expect(list.first.createdAt.millisecondsSinceEpoch, 2000);
    });

    test('maps exception to Err(StorageFailure)', () async {
      store.throwOnGetAll = true;
      final result = await repo.getAll();
      expect(result, isA<Err<List<TranslationResult>>>());
      expect((result as Err<List<TranslationResult>>).failure, isA<StorageFailure>());
    });
  });

  group('delete', () {
    test('returns Ok(null) on success', () async {
      final id = await store.insert(_sample());
      final result = await repo.delete(id);
      expect(result, isA<Ok<void>>());
      expect(await store.getAll(), isEmpty);
    });

    test('maps exception to Err(StorageFailure)', () async {
      store.throwOnDelete = true;
      final result = await repo.delete(1);
      expect((result as Err<void>).failure, isA<StorageFailure>());
    });
  });

  group('clear', () {
    test('returns Ok(null) on success', () async {
      await store.insert(_sample());
      final result = await repo.clear();
      expect(result, isA<Ok<void>>());
      expect(await store.getAll(), isEmpty);
    });

    test('maps exception to Err(StorageFailure)', () async {
      store.throwOnClear = true;
      final result = await repo.clear();
      expect((result as Err<void>).failure, isA<StorageFailure>());
    });
  });

  test('Language.name values are stable', () {
    expect(Language.ko.name, 'ko');
    expect(Language.ja.name, 'ja');
  });
}
