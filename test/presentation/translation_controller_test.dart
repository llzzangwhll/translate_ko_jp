import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/core/language.dart';
import 'package:translate_ko_jp/data/repositories/translation_repository.dart';
import 'package:translate_ko_jp/data/services/permission_service.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/domain/usecases/listen_speech.dart';
import 'package:translate_ko_jp/domain/usecases/speak_text.dart';
import 'package:translate_ko_jp/domain/usecases/translate_text.dart';
import 'package:translate_ko_jp/presentation/translation/translation_controller.dart';
import '../fakes/fake_inference_service.dart';
import '../fakes/fake_permission_service.dart';
import '../fakes/fake_speech_service.dart';
import '../fakes/fake_tts_service.dart';

TranslationController _build({
  required FakeInferenceService inference,
  required FakeSpeechService speech,
  required FakeTtsService tts,
  FakePermissionService? permission,
}) {
  final repo = TranslationRepositoryImpl(inference);
  return TranslationController(
    translateText: TranslateText(repo),
    listenSpeech: ListenSpeech(speech),
    speakText: SpeakText(tts),
    permissionService: permission ?? FakePermissionService(),
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

  test('multiple final results in one session translate only once', () async {
    final inference = FakeInferenceService(response: 'こんにちは');
    final speech = FakeSpeechService();
    final tts = FakeTtsService();
    final c = _build(inference: inference, speech: speech, tts: tts);
    var translated = 0;
    c.onTranslated = (_) => translated++;

    await c.toggleListening();
    // Dictation mode can emit several final results in one session.
    speech.emit('이것은', isFinal: true);
    await Future<void>.delayed(Duration.zero);
    speech.emit('이것은 무엇입니까?', isFinal: true);
    await Future<void>.delayed(Duration.zero);

    expect(translated, 1);
    expect(c.messages.length, 1);
    // The engine must be stopped after the first final result.
    expect(speech.listening, isFalse);
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

  // --- New permission tests ---

  test('permission denied → errorMessage set, isListening stays false, speech not started', () async {
    final speech = FakeSpeechService();
    final permission = FakePermissionService(result: MicPermission.denied);
    final c = _build(
      inference: FakeInferenceService(),
      speech: speech,
      tts: FakeTtsService(),
      permission: permission,
    );

    await c.toggleListening();

    expect(c.isListening.value, isFalse);
    expect(c.errorMessage.value, isNotEmpty);
    expect(c.errorMessage.value, contains('마이크 권한이 필요합니다'));
    expect(speech.listening, isFalse);
  });

  test('permission permanentlyDenied → permissionPermanentlyDenied true, errorMessage set', () async {
    final speech = FakeSpeechService();
    final permission = FakePermissionService(result: MicPermission.permanentlyDenied);
    final c = _build(
      inference: FakeInferenceService(),
      speech: speech,
      tts: FakeTtsService(),
      permission: permission,
    );

    await c.toggleListening();

    expect(c.isListening.value, isFalse);
    expect(c.permissionPermanentlyDenied.value, isTrue);
    expect(c.errorMessage.value, isNotEmpty);
    expect(c.errorMessage.value, contains('설정에서 허용해 주세요'));
    expect(speech.listening, isFalse);
  });

  test('openAppSettings calls permission service openSettings', () async {
    final permission = FakePermissionService(result: MicPermission.permanentlyDenied);
    final c = _build(
      inference: FakeInferenceService(),
      speech: FakeSpeechService(),
      tts: FakeTtsService(),
      permission: permission,
    );

    await c.openAppSettings();

    expect(permission.openSettingsCalls, 1);
  });

  test('permission granted clears errorMessage and starts listening', () async {
    final speech = FakeSpeechService();
    final permission = FakePermissionService(result: MicPermission.granted);
    final c = _build(
      inference: FakeInferenceService(),
      speech: speech,
      tts: FakeTtsService(),
      permission: permission,
    );
    // Pre-set an old error to ensure it's cleared
    c.errorMessage.value = 'old error';

    await c.toggleListening();

    expect(c.isListening.value, isTrue);
    expect(c.errorMessage.value, isEmpty);
    expect(speech.listening, isTrue);
    expect(c.permissionPermanentlyDenied.value, isFalse);
  });
}
