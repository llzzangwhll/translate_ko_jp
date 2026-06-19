import 'package:flutter_test/flutter_test.dart';

import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/domain/usecases/get_history.dart';
import 'package:translate_ko_jp/domain/usecases/delete_history_entry.dart';
import 'package:translate_ko_jp/domain/usecases/clear_history.dart';
import 'package:translate_ko_jp/presentation/history/history_controller.dart';

import '../../fakes/fake_history_repository.dart';
import '../../fakes/fake_tts_service.dart';

TranslationResult _entry({required int at, String src = '안녕', String tr = 'やあ'}) =>
    TranslationResult(
      sourceText: src,
      translatedText: tr,
      direction: LanguageDirection.koToJa(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(at),
    );

HistoryController _build(FakeHistoryRepository repo, FakeTtsService tts) {
  return HistoryController(
    getHistory: GetHistory(repo),
    deleteHistoryEntry: DeleteHistoryEntry(repo),
    clearHistory: ClearHistory(repo),
    tts: tts,
  );
}

void main() {
  late FakeHistoryRepository repo;
  late FakeTtsService tts;

  setUp(() {
    repo = FakeHistoryRepository();
    tts = FakeTtsService();
  });

  test('load populates entries newest-first and clears loading/error', () async {
    await repo.save(_entry(at: 1000));
    await repo.save(_entry(at: 3000));
    await repo.save(_entry(at: 2000));

    final c = _build(repo, tts);
    await c.load();

    expect(c.isLoading.value, isFalse);
    expect(c.errorMessage.value, isNull);
    expect(c.entries.map((e) => e.createdAt.millisecondsSinceEpoch).toList(),
        [3000, 2000, 1000]);
  });

  test('load sets errorMessage on failure', () async {
    repo.failGetAll = const StorageFailure('db down');
    final c = _build(repo, tts);
    await c.load();

    expect(c.entries, isEmpty);
    expect(c.errorMessage.value, 'db down');
    expect(c.isLoading.value, isFalse);
  });

  test('deleteEntry removes the row and reloads', () async {
    await repo.save(_entry(at: 1000, src: 'keep'));
    final r = await repo.save(_entry(at: 2000, src: 'drop'));
    final dropId = (r as Ok<int>).value;

    final c = _build(repo, tts);
    await c.load();
    expect(c.entries, hasLength(2));

    await c.deleteEntry(dropId);

    expect(repo.deletedIds, contains(dropId));
    expect(c.entries.map((e) => e.sourceText), ['keep']);
  });

  test('clearAll empties the list', () async {
    await repo.save(_entry(at: 1000));
    await repo.save(_entry(at: 2000));

    final c = _build(repo, tts);
    await c.load();
    await c.clearAll();

    expect(repo.clearCount, 1);
    expect(c.entries, isEmpty);
  });

  test('play speaks translatedText in the target language', () async {
    final entry = _entry(at: 1000); // ko->ja, target = ja
    final c = _build(repo, tts);

    await c.play(entry);

    expect(tts.spoken, hasLength(1));
    expect(tts.spoken.single.text, 'やあ');
    expect(tts.spoken.single.language.name, 'ja');
  });

  test('deleteEntry surfaces failure as errorMessage', () async {
    final r = await repo.save(_entry(at: 1000));
    final id = (r as Ok<int>).value;
    final c = _build(repo, tts);
    await c.load();

    repo.failDelete = const StorageFailure('del fail');
    await c.deleteEntry(id);

    expect(c.errorMessage.value, 'del fail');
  });

  test('deleteEntry on failure keeps existing entries intact', () async {
    await repo.save(_entry(at: 1000, src: 'keep'));
    final r = await repo.save(_entry(at: 2000, src: 'also keep'));
    final id = (r as Ok<int>).value;
    final c = _build(repo, tts);
    await c.load();
    expect(c.entries, hasLength(2));

    repo.failDelete = const StorageFailure('disk full');
    await c.deleteEntry(id);

    expect(c.errorMessage.value, isNotNull);
    expect(c.entries, hasLength(2));
  });

  test('play sets errorMessage when TTS throws', () async {
    final entry = _entry(at: 1000);
    tts.throwOnSpeak = Exception('TTS crashed');
    final c = _build(repo, tts);

    await c.play(entry);

    expect(c.errorMessage.value, isNotNull);
    expect(c.errorMessage.value, contains('재생 실패'));
  });
}
