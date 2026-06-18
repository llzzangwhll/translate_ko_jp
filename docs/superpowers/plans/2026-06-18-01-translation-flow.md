# 번역 플로우 (Translation Flow) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** STT→Gemma 번역→화면 표시→TTS의 핵심 통역 흐름을 계층화(Service/Repository/UseCase/ViewModel)하여 기존 `TranslationController`의 뒤엉킨 로직을 테스트 가능한 구조로 재구성한다.

**Architecture:** `speech_to_text`/`flutter_tts`/MethodChannel을 각각 Service 구현으로 격리하고, `TranslationRepository`가 추론 결과를 `Result<TranslationResult>`로 감싼다. UseCase가 단일 동작을 담당하고 `TranslationController`(GetX ViewModel)는 상태와 조율만 맡는다. 히스토리 저장은 `onTranslated` 시임으로 노출하여 통합 단계(05)에서 연결한다.

**Tech Stack:** Flutter, Dart 3, GetX, speech_to_text, flutter_tts, flutter_test

> 모든 시그니처는 `2026-06-18-00-INDEX.md`의 "공유 계약"과 정확히 일치해야 한다. 선행: `00-foundation` 완료.

---

### Task 1: 테스트용 Fake 더블

**Files:**
- Create: `test/fakes/fake_inference_service.dart`
- Create: `test/fakes/fake_speech_service.dart`
- Create: `test/fakes/fake_tts_service.dart`

> 이 Fake들은 번역 플로우 테스트의 기반이다. 모델 관리(02)는 충돌을 피해 `FakeInferenceServiceModel`을 따로 둔다.

- [ ] **Step 1: FakeInferenceService 작성**

`test/fakes/fake_inference_service.dart`:
```dart
import 'package:flutter/services.dart';
import 'package:translate_ko_jp/data/services/inference_service.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';

class FakeInferenceService implements InferenceService {
  bool exists;
  bool loaded;
  String response;
  Object? throwOnTranslate;
  String? lastText;
  LanguageDirection? lastDirection;

  FakeInferenceService({
    this.exists = true,
    this.loaded = true,
    this.response = 'こんにちは',
    this.throwOnTranslate,
  });

  @override
  Future<bool> modelExists() async => exists;

  @override
  Future<bool> isLoaded() async => loaded;

  @override
  Future<void> load({String? modelPath}) async => loaded = true;

  @override
  Future<String> translate({
    required String text,
    required LanguageDirection direction,
  }) async {
    lastText = text;
    lastDirection = direction;
    if (throwOnTranslate != null) throw throwOnTranslate!;
    return response;
  }

  @override
  Future<void> dispose() async {}
}
```

- [ ] **Step 2: FakeSpeechService 작성**

`test/fakes/fake_speech_service.dart`:
```dart
import 'package:translate_ko_jp/core/language.dart';
import 'package:translate_ko_jp/data/services/speech_service.dart';

class FakeSpeechService implements SpeechService {
  bool available;
  bool listening = false;
  Language? lastLanguage;
  void Function(SpeechResult)? _onResult;

  FakeSpeechService({this.available = true});

  @override
  Future<bool> initialize() async => available;

  @override
  bool get isAvailable => available;

  @override
  Future<void> listen({
    required Language language,
    required void Function(SpeechResult result) onResult,
  }) async {
    listening = true;
    lastLanguage = language;
    _onResult = onResult;
  }

  /// Test helper: simulate the plugin emitting a result.
  void emit(String text, {required bool isFinal}) =>
      _onResult?.call(SpeechResult(text, isFinal));

  @override
  Future<void> stop() async => listening = false;

  @override
  Future<void> cancel() async => listening = false;
}
```

- [ ] **Step 3: FakeTtsService 작성**

`test/fakes/fake_tts_service.dart`:
```dart
import 'package:translate_ko_jp/core/language.dart';
import 'package:translate_ko_jp/data/services/tts_service.dart';

class FakeTtsService implements TtsService {
  final List<({String text, Language language})> spoken = [];
  bool stopped = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> speak({required String text, required Language language}) async {
    spoken.add((text: text, language: language));
  }

  @override
  Future<void> stop() async => stopped = true;
}
```

- [ ] **Step 4: 정적 분석으로 검증**

Run: `flutter analyze test/fakes`
Expected: `No issues found!` (foundation 인터페이스가 존재해야 함)

- [ ] **Step 5: 커밋**

```bash
git add test/fakes/
git commit -m "test: add fakes for inference, speech, tts services"
```

---

### Task 2: TranslationRepository

**Files:**
- Create: `lib/data/repositories/translation_repository.dart`
- Test: `test/data/repositories/translation_repository_test.dart`

- [ ] **Step 1: 실패 테스트 작성**

`test/data/repositories/translation_repository_test.dart`:
```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/data/repositories/translation_repository.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import '../../fakes/fake_inference_service.dart';

void main() {
  test('returns Ok with translated text on success', () async {
    final inference = FakeInferenceService(response: 'こんにちは');
    final repo = TranslationRepositoryImpl(inference);

    final result = await repo.translate(
      text: '안녕하세요',
      direction: LanguageDirection.koToJa(),
    );

    expect(result, isA<Ok<TranslationResult>>());
    final value = (result as Ok<TranslationResult>).value;
    expect(value.sourceText, '안녕하세요');
    expect(value.translatedText, 'こんにちは');
    expect(value.direction, LanguageDirection.koToJa());
    expect(inference.lastDirection, LanguageDirection.koToJa());
  });

  test('maps PlatformException to InferenceFailure', () async {
    final inference = FakeInferenceService(
      throwOnTranslate: PlatformException(code: 'TRANSLATE_FAILED', message: 'boom'),
    );
    final repo = TranslationRepositoryImpl(inference);

    final result = await repo.translate(
      text: '테스트',
      direction: LanguageDirection.koToJa(),
    );

    expect(result, isA<Err<TranslationResult>>());
    expect((result as Err<TranslationResult>).failure, isA<InferenceFailure>());
    expect(result.failure.message, contains('boom'));
  });

  test('returns InferenceFailure when model produces empty output', () async {
    final inference = FakeInferenceService(response: '   ');
    final repo = TranslationRepositoryImpl(inference);

    final result = await repo.translate(
      text: '테스트',
      direction: LanguageDirection.koToJa(),
    );

    expect(result, isA<Err<TranslationResult>>());
    expect((result as Err<TranslationResult>).failure, isA<InferenceFailure>());
  });
}
```

- [ ] **Step 2: 실행하여 실패 확인**

Run: `flutter test test/data/repositories/translation_repository_test.dart`
Expected: FAIL (`TranslationRepositoryImpl` 미정의)

- [ ] **Step 3: 구현**

`lib/data/repositories/translation_repository.dart`:
```dart
import 'package:flutter/services.dart';
import '../../core/result.dart';
import '../../core/failure.dart';
import '../../domain/entities/language_direction.dart';
import '../../domain/entities/translation_result.dart';
import '../services/inference_service.dart';

abstract interface class TranslationRepository {
  Future<Result<TranslationResult>> translate({
    required String text,
    required LanguageDirection direction,
  });
}

class TranslationRepositoryImpl implements TranslationRepository {
  final InferenceService _inference;
  TranslationRepositoryImpl(this._inference);

  @override
  Future<Result<TranslationResult>> translate({
    required String text,
    required LanguageDirection direction,
  }) async {
    try {
      final raw = await _inference.translate(text: text, direction: direction);
      final translated = raw.trim();
      if (translated.isEmpty) {
        return const Err(InferenceFailure('번역 결과가 비어 있습니다'));
      }
      return Ok(TranslationResult(
        sourceText: text,
        translatedText: translated,
        direction: direction,
        createdAt: DateTime.now(),
      ));
    } on PlatformException catch (e) {
      return Err(InferenceFailure(e.message ?? '번역 실패'));
    } catch (e) {
      return Err(InferenceFailure(e.toString()));
    }
  }
}
```

- [ ] **Step 4: 실행하여 통과 확인**

Run: `flutter test test/data/repositories/translation_repository_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: 커밋**

```bash
git add lib/data/repositories/translation_repository.dart test/data/repositories/translation_repository_test.dart
git commit -m "feat: add TranslationRepository wrapping inference in Result"
```

---

### Task 3: UseCase — TranslateText / SpeakText / ListenSpeech

**Files:**
- Create: `lib/domain/usecases/translate_text.dart`
- Create: `lib/domain/usecases/speak_text.dart`
- Create: `lib/domain/usecases/listen_speech.dart`
- Test: `test/domain/usecases/translate_text_test.dart`
- Test: `test/domain/usecases/speak_text_test.dart`

- [ ] **Step 1: 실패 테스트 작성 (TranslateText + SpeakText)**

`test/domain/usecases/translate_text_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/data/repositories/translation_repository.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/usecases/translate_text.dart';
import '../../fakes/fake_inference_service.dart';

void main() {
  test('TranslateText delegates to repository and returns Result', () async {
    final repo = TranslationRepositoryImpl(FakeInferenceService(response: 'こんにちは'));
    final useCase = TranslateText(repo);

    final result = await useCase(
      text: '안녕하세요',
      direction: LanguageDirection.koToJa(),
    );

    expect(result.isOk, isTrue);
    expect(result.valueOrNull!.translatedText, 'こんにちは');
  });
}
```

`test/domain/usecases/speak_text_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/core/language.dart';
import 'package:translate_ko_jp/domain/usecases/speak_text.dart';
import '../../fakes/fake_tts_service.dart';

void main() {
  test('SpeakText forwards text and language to TtsService', () async {
    final tts = FakeTtsService();
    final useCase = SpeakText(tts);

    await useCase(text: 'こんにちは', language: Language.ja);

    expect(tts.spoken.single.text, 'こんにちは');
    expect(tts.spoken.single.language, Language.ja);
  });
}
```

- [ ] **Step 2: 실행하여 실패 확인**

Run: `flutter test test/domain/usecases/`
Expected: FAIL (UseCase 미정의)

- [ ] **Step 3: 구현**

`lib/domain/usecases/translate_text.dart`:
```dart
import '../../core/result.dart';
import '../../data/repositories/translation_repository.dart';
import '../entities/language_direction.dart';
import '../entities/translation_result.dart';

class TranslateText {
  final TranslationRepository _repository;
  TranslateText(this._repository);

  Future<Result<TranslationResult>> call({
    required String text,
    required LanguageDirection direction,
  }) {
    return _repository.translate(text: text, direction: direction);
  }
}
```

`lib/domain/usecases/speak_text.dart`:
```dart
import '../../core/language.dart';
import '../../data/services/tts_service.dart';

class SpeakText {
  final TtsService _tts;
  SpeakText(this._tts);

  Future<void> call({required String text, required Language language}) {
    return _tts.speak(text: text, language: language);
  }
}
```

`lib/domain/usecases/listen_speech.dart`:
```dart
import '../../core/language.dart';
import '../../data/services/speech_service.dart';

class ListenSpeech {
  final SpeechService _speech;
  ListenSpeech(this._speech);

  bool get isAvailable => _speech.isAvailable;
  Future<bool> initialize() => _speech.initialize();

  Future<void> call({
    required Language language,
    required void Function(SpeechResult result) onResult,
  }) {
    return _speech.listen(language: language, onResult: onResult);
  }

  Future<void> stop() => _speech.stop();
  Future<void> cancel() => _speech.cancel();
}
```

- [ ] **Step 4: 실행하여 통과 확인**

Run: `flutter test test/domain/usecases/`
Expected: PASS (2 tests)

- [ ] **Step 5: 커밋**

```bash
git add lib/domain/usecases/ test/domain/usecases/
git commit -m "feat: add TranslateText, SpeakText, ListenSpeech use cases"
```

---

### Task 4: TranslationController (ViewModel)

**Files:**
- Create: `lib/presentation/translation/translation_controller.dart`
- Test: `test/presentation/translation_controller_test.dart`

- [ ] **Step 1: 실패 테스트 작성**

`test/presentation/translation_controller_test.dart`:
```dart
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
}
```

- [ ] **Step 2: 실행하여 실패 확인**

Run: `flutter test test/presentation/translation_controller_test.dart`
Expected: FAIL (`TranslationController` 미정의)

- [ ] **Step 3: 구현**

`lib/presentation/translation/translation_controller.dart`:
```dart
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../core/language.dart';
import '../../core/result.dart';
import '../../domain/entities/language_direction.dart';
import '../../domain/entities/translation_result.dart';
import '../../domain/usecases/listen_speech.dart';
import '../../domain/usecases/speak_text.dart';
import '../../domain/usecases/translate_text.dart';
import '../../data/services/speech_service.dart';

class TranslationController extends GetxController {
  final TranslateText _translateText;
  final ListenSpeech _listenSpeech;
  final SpeakText _speakText;

  TranslationController({
    required TranslateText translateText,
    required ListenSpeech listenSpeech,
    required SpeakText speakText,
  })  : _translateText = translateText,
        _listenSpeech = listenSpeech,
        _speakText = speakText;

  final direction = LanguageDirection.koToJa().obs;
  final sourceText = ''.obs;
  final translatedText = ''.obs;
  final isListening = false.obs;
  final isTranslating = false.obs;
  final autoSpeak = false.obs;
  final lastResult = Rxn<TranslationResult>();
  final errorMessage = ''.obs;

  /// Integration seam (plan 05): called with each successful translation so
  /// the history flow can persist it. Not wired here.
  void Function(TranslationResult result)? onTranslated;

  Language get sourceLanguage => direction.value.from;
  Language get targetLanguage => direction.value.to;

  Future<void> onReady() async {
    super.onReady();
    await _listenSpeech.initialize();
  }

  Future<void> toggleListening() async {
    if (isListening.value) {
      await _listenSpeech.stop();
      isListening.value = false;
      if (sourceText.value.trim().isNotEmpty) await translate();
      return;
    }
    if (!_listenSpeech.isAvailable) {
      errorMessage.value = '음성 인식을 사용할 수 없습니다';
      return;
    }
    isListening.value = true;
    translatedText.value = '';
    await _listenSpeech(
      language: sourceLanguage,
      onResult: _onSpeechResult,
    );
  }

  void _onSpeechResult(SpeechResult result) {
    sourceText.value = result.text;
    if (result.isFinal && result.text.trim().isNotEmpty) {
      isListening.value = false;
      translate();
    }
  }

  Future<void> translate() async {
    final text = sourceText.value.trim();
    if (text.isEmpty) return;

    isTranslating.value = true;
    translatedText.value = '';
    errorMessage.value = '';

    final result = await _translateText(text: text, direction: direction.value);
    switch (result) {
      case Ok(value: final r):
        translatedText.value = r.translatedText;
        lastResult.value = r;
        onTranslated?.call(r);
        if (autoSpeak.value) {
          await _speakText(text: r.translatedText, language: targetLanguage);
        }
      case Err(failure: final f):
        errorMessage.value = f.message;
    }
    isTranslating.value = false;
  }

  Future<void> speakSource() async {
    final text = sourceText.value.trim();
    if (text.isEmpty) return;
    await _speakText(text: text, language: sourceLanguage);
  }

  Future<void> speakTranslation() async {
    if (translatedText.value.isEmpty) return;
    await _speakText(text: translatedText.value, language: targetLanguage);
  }

  void toggleDirection() {
    direction.value = direction.value.reversed;
    final old = sourceText.value;
    sourceText.value = translatedText.value;
    translatedText.value = old;
  }

  void clear() {
    sourceText.value = '';
    translatedText.value = '';
    errorMessage.value = '';
  }

  void copyTranslation() {
    if (translatedText.value.isEmpty) return;
    Clipboard.setData(ClipboardData(text: translatedText.value));
  }
}
```

- [ ] **Step 4: 실행하여 통과 확인**

Run: `flutter test test/presentation/translation_controller_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: 커밋**

```bash
git add lib/presentation/translation/translation_controller.dart test/presentation/translation_controller_test.dart
git commit -m "feat: add TranslationController view model with history seam"
```

---

### Task 5: SpeechServiceImpl (speech_to_text 래핑)

**Files:**
- Create: `lib/data/services/speech_service_impl.dart`
- Test: `test/data/services/speech_service_impl_test.dart`

> 플러그인 내부(네이티브 STT)는 단위 테스트 대상이 아니다. 여기서는 생성·정적분석과, 결과 매핑 로직(콜백→SpeechResult)을 검증한다.

- [ ] **Step 1: 구현**

`lib/data/services/speech_service_impl.dart`:
```dart
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../core/language.dart';
import 'speech_service.dart';

class SpeechServiceImpl implements SpeechService {
  final stt.SpeechToText _speech;
  bool _available = false;

  SpeechServiceImpl({stt.SpeechToText? engine})
      : _speech = engine ?? stt.SpeechToText();

  @override
  Future<bool> initialize() async {
    _available = await _speech.initialize(
      onError: (_) {},
      onStatus: (_) {},
    );
    return _available;
  }

  @override
  bool get isAvailable => _available;

  @override
  Future<void> listen({
    required Language language,
    required void Function(SpeechResult result) onResult,
  }) async {
    await _speech.listen(
      localeId: language.sttLocale,
      onResult: (r) => onResult(SpeechResult(r.recognizedWords, r.finalResult)),
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        cancelOnError: true,
        partialResults: true,
      ),
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}
```

- [ ] **Step 2: 정적 분석으로 검증**

Run: `flutter analyze lib/data/services/speech_service_impl.dart`
Expected: `No issues found!`

- [ ] **Step 3: 스모크 테스트 작성**

`test/data/services/speech_service_impl_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/data/services/speech_service_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('isAvailable is false before initialize', () {
    final service = SpeechServiceImpl();
    expect(service.isAvailable, isFalse);
  });
}
```

- [ ] **Step 4: 실행하여 통과 확인**

Run: `flutter test test/data/services/speech_service_impl_test.dart`
Expected: PASS (1 test)

- [ ] **Step 5: 커밋**

```bash
git add lib/data/services/speech_service_impl.dart test/data/services/speech_service_impl_test.dart
git commit -m "feat: add SpeechServiceImpl wrapping speech_to_text"
```

---

### Task 6: TtsServiceImpl (flutter_tts 래핑)

**Files:**
- Create: `lib/data/services/tts_service_impl.dart`
- Test: `test/data/services/tts_service_impl_test.dart`

- [ ] **Step 1: 구현**

`lib/data/services/tts_service_impl.dart`:
```dart
import 'package:flutter_tts/flutter_tts.dart';
import '../../core/language.dart';
import 'tts_service.dart';

class TtsServiceImpl implements TtsService {
  final FlutterTts _tts;
  TtsServiceImpl({FlutterTts? engine}) : _tts = engine ?? FlutterTts();

  @override
  Future<void> initialize() async {
    await _tts.setVolume(1.0);
    await _tts.setSpeechRate(0.45);
  }

  @override
  Future<void> speak({required String text, required Language language}) async {
    await _tts.setLanguage(language.ttsCode);
    await _tts.speak(text);
  }

  @override
  Future<void> stop() => _tts.stop();
}
```

- [ ] **Step 2: 정적 분석으로 검증**

Run: `flutter analyze lib/data/services/tts_service_impl.dart`
Expected: `No issues found!`

- [ ] **Step 3: 스모크 테스트 작성**

`test/data/services/tts_service_impl_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/data/services/tts_service_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('constructs without throwing', () {
    expect(TtsServiceImpl.new, returnsNormally);
  });
}
```

- [ ] **Step 4: 실행하여 통과 확인**

Run: `flutter test test/data/services/tts_service_impl_test.dart`
Expected: PASS (1 test)

- [ ] **Step 5: 커밋**

```bash
git add lib/data/services/tts_service_impl.dart test/data/services/tts_service_impl_test.dart
git commit -m "feat: add TtsServiceImpl wrapping flutter_tts"
```

---

### Task 7: MediaPipeInferenceService (MethodChannel 래핑)

**Files:**
- Create: `lib/data/services/mediapipe_inference_service.dart`
- Test: `test/data/services/mediapipe_inference_service_test.dart`

> 채널 계약(INDEX): `com.example.translate_ko_jp/gemma`. `translate`의 sourceLang/targetLang은 `Language.promptLabel`.

- [ ] **Step 1: 실패 테스트 작성 (MethodChannel 모킹)**

`test/data/services/mediapipe_inference_service_test.dart`:
```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/data/services/mediapipe_inference_service.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.translate_ko_jp/gemma');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('translate sends promptLabel langs and returns response', () async {
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return 'こんにちは';
    });

    final service = MediaPipeInferenceService();
    final out = await service.translate(
      text: '안녕하세요',
      direction: LanguageDirection.koToJa(),
    );

    expect(out, 'こんにちは');
    expect(captured!.method, 'translate');
    expect(captured!.arguments['text'], '안녕하세요');
    expect(captured!.arguments['sourceLang'], 'Korean');
    expect(captured!.arguments['targetLang'], 'Japanese');
  });

  test('isLoaded returns channel boolean', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isModelLoaded');
      return true;
    });
    final service = MediaPipeInferenceService();
    expect(await service.isLoaded(), isTrue);
  });

  test('modelExists swallows PlatformException as false', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'X');
    });
    final service = MediaPipeInferenceService();
    expect(await service.modelExists(), isFalse);
  });
}
```

- [ ] **Step 2: 실행하여 실패 확인**

Run: `flutter test test/data/services/mediapipe_inference_service_test.dart`
Expected: FAIL (`MediaPipeInferenceService` 미정의)

- [ ] **Step 3: 구현**

`lib/data/services/mediapipe_inference_service.dart`:
```dart
import 'package:flutter/services.dart';
import '../../domain/entities/language_direction.dart';
import 'inference_service.dart';

class MediaPipeInferenceService implements InferenceService {
  static const _channel = MethodChannel('com.example.translate_ko_jp/gemma');

  @override
  Future<bool> modelExists() async {
    try {
      return await _channel.invokeMethod('checkModelExists') == true;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> isLoaded() async {
    try {
      return await _channel.invokeMethod('isModelLoaded') == true;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> load({String? modelPath}) async {
    final args = modelPath != null ? {'modelPath': modelPath} : null;
    final ok = await _channel.invokeMethod('loadModel', args);
    if (ok != true) {
      throw PlatformException(code: 'LOAD_FAILED', message: '모델 로딩 실패');
    }
  }

  @override
  Future<String> translate({
    required String text,
    required LanguageDirection direction,
  }) async {
    final result = await _channel.invokeMethod('translate', {
      'text': text,
      'sourceLang': direction.from.promptLabel,
      'targetLang': direction.to.promptLabel,
    });
    return (result as String?) ?? '';
  }

  @override
  Future<void> dispose() async {}
}
```

- [ ] **Step 4: 실행하여 통과 확인**

Run: `flutter test test/data/services/mediapipe_inference_service_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: 커밋**

```bash
git add lib/data/services/mediapipe_inference_service.dart test/data/services/mediapipe_inference_service_test.dart
git commit -m "feat: add MediaPipeInferenceService MethodChannel wrapper"
```

---

### Task 8: DI 등록 — registerTranslationDeps()

**Files:**
- Create: `lib/app/translation_deps.dart`

- [ ] **Step 1: 구현**

`lib/app/translation_deps.dart`:
```dart
import 'package:get/get.dart';
import '../data/services/inference_service.dart';
import '../data/services/mediapipe_inference_service.dart';
import '../data/services/speech_service.dart';
import '../data/services/speech_service_impl.dart';
import '../data/services/tts_service.dart';
import '../data/services/tts_service_impl.dart';
import '../data/repositories/translation_repository.dart';
import '../domain/usecases/listen_speech.dart';
import '../domain/usecases/speak_text.dart';
import '../domain/usecases/translate_text.dart';
import '../presentation/translation/translation_controller.dart';

void registerTranslationDeps() {
  // Services (shared singletons)
  Get.lazyPut<InferenceService>(() => MediaPipeInferenceService(), fenix: true);
  Get.lazyPut<SpeechService>(() => SpeechServiceImpl()..initialize(), fenix: true);
  Get.lazyPut<TtsService>(() => TtsServiceImpl()..initialize(), fenix: true);

  // Repository
  Get.lazyPut<TranslationRepository>(
    () => TranslationRepositoryImpl(Get.find<InferenceService>()),
    fenix: true,
  );

  // Controller
  Get.lazyPut<TranslationController>(
    () => TranslationController(
      translateText: TranslateText(Get.find<TranslationRepository>()),
      listenSpeech: ListenSpeech(Get.find<SpeechService>()),
      speakText: SpeakText(Get.find<TtsService>()),
    ),
    fenix: true,
  );
}
```

- [ ] **Step 2: 정적 분석으로 검증**

Run: `flutter analyze lib/app/translation_deps.dart`
Expected: `No issues found!`

- [ ] **Step 3: 커밋**

```bash
git add lib/app/translation_deps.dart
git commit -m "feat: add translation flow DI registration"
```

---

### Task 9: TranslationScreen (View)

**Files:**
- Create: `lib/presentation/translation/translation_screen.dart`
- Test: `test/presentation/translation_screen_test.dart`

- [ ] **Step 1: 위젯 스모크 테스트 작성**

`test/presentation/translation_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:translate_ko_jp/data/repositories/translation_repository.dart';
import 'package:translate_ko_jp/domain/usecases/listen_speech.dart';
import 'package:translate_ko_jp/domain/usecases/speak_text.dart';
import 'package:translate_ko_jp/domain/usecases/translate_text.dart';
import 'package:translate_ko_jp/presentation/translation/translation_controller.dart';
import 'package:translate_ko_jp/presentation/translation/translation_screen.dart';
import '../fakes/fake_inference_service.dart';
import '../fakes/fake_speech_service.dart';
import '../fakes/fake_tts_service.dart';

void main() {
  testWidgets('renders source/translated panels and mic button', (tester) async {
    final repo = TranslationRepositoryImpl(FakeInferenceService());
    Get.put<TranslationController>(TranslationController(
      translateText: TranslateText(repo),
      listenSpeech: ListenSpeech(FakeSpeechService()),
      speakText: SpeakText(FakeTtsService()),
    ));

    await tester.pumpWidget(const GetMaterialApp(home: TranslationScreen()));

    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.byType(TranslationScreen), findsOneWidget);
    Get.reset();
  });
}
```

- [ ] **Step 2: 실행하여 실패 확인**

Run: `flutter test test/presentation/translation_screen_test.dart`
Expected: FAIL (`TranslationScreen` 미정의)

- [ ] **Step 3: 구현**

`lib/presentation/translation/translation_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../app/routes.dart';
import 'translation_controller.dart';

class TranslationScreen extends GetView<TranslationController> {
  const TranslationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('한↔일 통역'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Get.toNamed(Routes.history),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Obx(() => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(controller.sourceLanguage.nativeLabel),
                    IconButton(
                      icon: const Icon(Icons.swap_horiz),
                      onPressed: controller.toggleDirection,
                    ),
                    Text(controller.targetLanguage.nativeLabel),
                  ],
                )),
            const SizedBox(height: 12),
            Expanded(
              child: Obx(() => _Panel(
                    title: controller.sourceLanguage.nativeLabel,
                    text: controller.sourceText.value,
                    onSpeak: controller.speakSource,
                  )),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Obx(() => _Panel(
                    title: controller.targetLanguage.nativeLabel,
                    text: controller.isTranslating.value
                        ? '번역 중...'
                        : controller.translatedText.value,
                    onSpeak: controller.speakTranslation,
                    onCopy: controller.copyTranslation,
                  )),
            ),
            const SizedBox(height: 12),
            Obx(() => controller.errorMessage.value.isEmpty
                ? const SizedBox.shrink()
                : Text(controller.errorMessage.value,
                    style: const TextStyle(color: Colors.red))),
            Center(
              child: Obx(() => FloatingActionButton.large(
                    onPressed: controller.toggleListening,
                    backgroundColor:
                        controller.isListening.value ? Colors.red : null,
                    child: Icon(
                        controller.isListening.value ? Icons.stop : Icons.mic),
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String text;
  final VoidCallback? onSpeak;
  final VoidCallback? onCopy;
  const _Panel({
    required this.title,
    required this.text,
    this.onSpeak,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                if (onSpeak != null)
                  IconButton(
                      icon: const Icon(Icons.volume_up), onPressed: onSpeak),
                if (onCopy != null)
                  IconButton(icon: const Icon(Icons.copy), onPressed: onCopy),
              ],
            ),
            Expanded(child: SingleChildScrollView(child: Text(text))),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 실행하여 통과 확인**

Run: `flutter test test/presentation/translation_screen_test.dart`
Expected: PASS (1 test)

- [ ] **Step 5: 커밋**

```bash
git add lib/presentation/translation/translation_screen.dart test/presentation/translation_screen_test.dart
git commit -m "feat: add TranslationScreen bound to controller"
```

---

## 완료 기준

- [ ] `flutter test test/data test/domain/usecases test/presentation` 전부 통과
- [ ] `flutter analyze lib/data lib/domain lib/presentation/translation lib/app/translation_deps.dart` 이슈 없음
- [ ] 모든 타입/메서드가 INDEX 공유 계약과 일치 (`InferenceService`, `SpeechService`, `TtsService`, `TranslationRepository`, `Result`/`Failure`)
- [ ] `TranslationController.onTranslated` 시임이 노출되어 05에서 히스토리 저장 연결 가능
- [ ] 기존 `lib/controllers/translation_controller.dart` / `lib/services/gemma_service.dart` 는 05(통합)에서 제거 — 이 플로우에서는 건드리지 않음
