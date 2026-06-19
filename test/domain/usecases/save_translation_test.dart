import 'package:flutter_test/flutter_test.dart';

import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/domain/usecases/save_translation.dart';

import '../../fakes/fake_history_repository.dart';

TranslationResult _sample() => TranslationResult(
      sourceText: '안녕',
      translatedText: 'やあ',
      direction: LanguageDirection.koToJa(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );

void main() {
  late FakeHistoryRepository repo;
  late SaveTranslation save;

  setUp(() {
    repo = FakeHistoryRepository();
    save = SaveTranslation(repo);
  });

  test('delegates to repository.save and returns Ok(id)', () async {
    final result = await save(_sample());
    expect(result, isA<Ok<int>>());
    expect(repo.savedArgs, hasLength(1));
    expect(repo.savedArgs.single.translatedText, 'やあ');
  });

  test('propagates Err on failure', () async {
    repo.failSave = const StorageFailure('boom');
    final result = await save(_sample());
    expect(result, isA<Err<int>>());
    expect((result as Err<int>).failure, isA<StorageFailure>());
  });
}
