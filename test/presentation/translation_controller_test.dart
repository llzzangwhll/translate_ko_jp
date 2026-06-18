import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/core/language.dart';
import 'package:translate_ko_jp/data/repositories/translation_repository.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/domain/usecases/listen_speech.dart';
import 'package:translate_ko_jp/domain/usecases/speak_text.dart';
import 'package:translate_ko_jp/domain/usecases/translate_text.dart';
import 'package:translate_ko_jp/presentation/translation/translation_controller.dart';
import '../fakes/fake_inference_service.dart';
import '../fakes/fake_speech_service.dart';
import '../fakes/fake_tts_service.dart';

TranslationController _build({
  required FakeInferenceService inference,
  required FakeSpeechService speech,
  required FakeTtsService tts,
}) {
  final repo = TranslationRepositoryImpl(inference);
  return TranslationController(
    translateText: TranslateText(repo),
    listenSpeech: ListenSpeech(speech),
    speakText: SpeakText(tts),
  );
}

void main() {
  test('final speech result triggers translation and updates state', () async {
    final inference = FakeInferenceService(response: 'こんにちは');
    final speech = FakeSpeechService();
    final tts = FakeTtsService();
    final c = _build(inference: inference, speech: speech, tts: tts);

    await c.toggleListening();
    speech.emit('안녕하세요', isFinal: false);
    expect(c.sourceText.value, '안녕하세요');

    speech.emit('안녕하세요', isFinal: true);
    await Future<void>.delayed(Duration.zero);

    expect(c.translatedText.value, 'こんにちは');
    expect(c.lastResult.value, isA<TranslationResult>());
    expect(c.isTranslating.value, isFalse);
  });

  test('onTranslated seam fires with the produced result', () async {
    final c = _build(
      inference: FakeInferenceService(response: 'こんにちは'),
      speech: FakeSpeechService(),
      tts: FakeTtsService(),
    );
    TranslationResult? captured;
    c.onTranslated = (r) => captured = r;

    c.sourceText.value = '안녕';
    await c.translate();

    expect(captured, isNotNull);
    expect(captured!.translatedText, 'こんにちは');
  });

  test('toggleDirection swaps source and translated and flips direction', () {
    final c = _build(
      inference: FakeInferenceService(),
      speech: FakeSpeechService(),
      tts: FakeTtsService(),
    );
    c.sourceText.value = '안녕';
    c.translatedText.value = 'こんにちは';
    expect(c.direction.value, LanguageDirection.koToJa());

    c.toggleDirection();

    expect(c.direction.value, LanguageDirection.jaToKo());
    expect(c.sourceText.value, 'こんにちは');
    expect(c.translatedText.value, '안녕');
  });

  test('auto-speaks translation when autoSpeak is on', () async {
    final tts = FakeTtsService();
    final c = _build(
      inference: FakeInferenceService(response: 'こんにちは'),
      speech: FakeSpeechService(),
      tts: tts,
    );
    c.autoSpeak.value = true;
    c.sourceText.value = '안녕';

    await c.translate();

    expect(tts.spoken.single.text, 'こんにちは');
    expect(tts.spoken.single.language, Language.ja);
  });

  test('translate() sets errorMessage on PlatformException and resets isTranslating', () async {
    final c = _build(
      inference: FakeInferenceService(
        throwOnTranslate: PlatformException(code: 'TRANSLATE_FAILED', message: 'boom'),
      ),
      speech: FakeSpeechService(),
      tts: FakeTtsService(),
    );
    c.sourceText.value = '안녕';

    await c.translate();

    expect(c.errorMessage.value, contains('boom'));
    expect(c.translatedText.value, isEmpty);
    expect(c.isTranslating.value, isFalse);
  });
}
