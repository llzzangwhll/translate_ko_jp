import 'package:flutter_test/flutter_test.dart';

import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/domain/usecases/get_history.dart';

import '../../fakes/fake_history_repository.dart';

TranslationResult _sample({required int at}) => TranslationResult(
      sourceText: 's$at',
      translatedText: 't$at',
      direction: LanguageDirection.koToJa(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(at),
    );

void main() {
  late FakeHistoryRepository repo;
  late GetHistory getHistory;

  setUp(() {
    repo = FakeHistoryRepository();
    getHistory = GetHistory(repo);
  });

  test('returns Ok(list) newest-first', () async {
    await repo.save(_sample(at: 1000));
    await repo.save(_sample(at: 3000));
    await repo.save(_sample(at: 2000));

    final result = await getHistory();
    expect(result, isA<Ok<List<TranslationResult>>>());
    final list = (result as Ok<List<TranslationResult>>).value;
    expect(list.map((e) => e.createdAt.millisecondsSinceEpoch).toList(),
        [3000, 2000, 1000]);
  });

  test('propagates Err on failure', () async {
    repo.failGetAll = const StorageFailure('boom');
    final result = await getHistory();
    expect((result as Err<List<TranslationResult>>).failure, isA<StorageFailure>());
  });
}
