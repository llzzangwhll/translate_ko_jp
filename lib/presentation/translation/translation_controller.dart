import 'dart:async';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../core/failure.dart';
import '../../core/language.dart';
import '../../core/result.dart';
import '../../domain/entities/language_direction.dart';
import '../../domain/entities/translation_result.dart';
import '../../domain/usecases/listen_speech.dart';
import '../../domain/usecases/speak_text.dart';
import '../../domain/usecases/translate_text.dart';
import '../../domain/usecases/warm_up_model.dart';
import '../../domain/usecases/get_engine_backend.dart';
import '../../data/services/permission_service.dart';
import '../../data/services/speech_service.dart';

class TranslationController extends GetxController {
  final TranslateText _translateText;
  final ListenSpeech _listenSpeech;
  final SpeakText _speakText;
  final PermissionService _permission;
  final WarmUpModel? _warmUpModel;
  final GetEngineBackend? _getEngineBackend;

  TranslationController({
    required TranslateText translateText,
    required ListenSpeech listenSpeech,
    required SpeakText speakText,
    required PermissionService permissionService,
    WarmUpModel? warmUpModel,
    GetEngineBackend? getEngineBackend,
  })  : _translateText = translateText,
        _listenSpeech = listenSpeech,
        _speakText = speakText,
        _permission = permissionService,
        _warmUpModel = warmUpModel,
        _getEngineBackend = getEngineBackend;

  final direction = LanguageDirection.koToJa().obs;
  final sourceText = ''.obs;
  final translatedText = ''.obs;
  final isListening = false.obs;
  final isTranslating = false.obs;
  final autoSpeak = true.obs;
  final lastResult = Rxn<TranslationResult>();
  final errorMessage = ''.obs;
  final permissionPermanentlyDenied = false.obs;

  /// Warm-up state for the manual "워밍업" button. [isWarmingUp] drives the
  /// button spinner; [warmedUp] hides/disables it once done.
  final isWarmingUp = false.obs;
  final warmedUp = false.obs;

  /// Backend the engine is running on ('gpu', 'cpu', 'none', 'unknown', or
  /// empty before it's been queried). Shown to the user for diagnostics.
  final engineBackend = ''.obs;

  /// Conversation log for the face-to-face interpreting UI: each completed
  /// translation is appended (oldest first), so both speakers can scroll back
  /// through the exchange.
  final messages = <TranslationResult>[].obs;

  /// The language currently being listened for, or null when idle. Drives which
  /// mic button shows the active (recording) state.
  Language? get activeSource =>
      isListening.value ? direction.value.from : null;

  /// Integration seam (plan 05): called with each successful translation so
  /// the history flow can persist it. Not wired here.
  void Function(TranslationResult result)? onTranslated;

  Language get sourceLanguage => direction.value.from;
  Language get targetLanguage => direction.value.to;

  /// Guards against the speech engine emitting more than one final result per
  /// listen session. In dictation mode the plugin can report a final result
  /// when the speaker pauses and then again when they continue, which would
  /// otherwise trigger translate() multiple times and duplicate the output
  /// (e.g. "이것은" then "이것은 무엇입니까?"). Reset when a new session starts.
  bool _finalized = false;

  @override
  Future<void> onReady() async {
    super.onReady();
    await _listenSpeech.initialize();
    final getBackend = _getEngineBackend;
    if (getBackend != null) {
      engineBackend.value = await getBackend();
    }
  }

  Future<void> toggleListening() async {
    if (isListening.value) {
      _finalized = true; // ignore any late final result from the engine
      await _listenSpeech.stop();
      isListening.value = false;
      if (sourceText.value.trim().isNotEmpty) await translate();
      return;
    }

    // Request microphone permission before starting listening
    final perm = await _permission.ensureMicrophone();
    switch (perm) {
      case MicPermission.granted:
        permissionPermanentlyDenied.value = false;
        errorMessage.value = '';
      case MicPermission.denied:
        errorMessage.value =
            const PermissionFailure('마이크 권한이 필요합니다. 권한을 허용해 주세요.').message;
        return;
      case MicPermission.permanentlyDenied:
        permissionPermanentlyDenied.value = true;
        errorMessage.value =
            const PermissionFailure('마이크 권한이 거부되었습니다. 설정에서 허용해 주세요.').message;
        return;
    }

    if (!_listenSpeech.isAvailable) {
      errorMessage.value = '음성 인식을 사용할 수 없습니다';
      return;
    }
    isListening.value = true;
    _finalized = false;
    sourceText.value = '';
    translatedText.value = '';
    await _listenSpeech(
      language: sourceLanguage,
      onResult: _onSpeechResult,
    );
  }

  /// Mic tap from the two-button conversation UI. Tapping while idle sets the
  /// direction from the tapped language and starts listening; tapping while
  /// listening stops and translates (regardless of which mic was tapped).
  Future<void> toggleListenFor(Language source) async {
    if (isListening.value) {
      await toggleListening();
      return;
    }
    direction.value = source == Language.ko
        ? LanguageDirection.koToJa()
        : LanguageDirection.jaToKo();
    await toggleListening();
  }

  void _onSpeechResult(SpeechResult result) {
    if (_finalized) return; // a final result was already handled this session
    sourceText.value = result.text;
    if (result.isFinal && result.text.trim().isNotEmpty) {
      _finalized = true;
      isListening.value = false;
      unawaited(_listenSpeech.stop()); // stop the engine so no further finals fire
      unawaited(translate());
    }
  }

  Future<void> translate() async {
    final text = sourceText.value.trim();
    if (text.isEmpty) return;

    isTranslating.value = true;
    try {
      translatedText.value = '';
      errorMessage.value = '';

      final result = await _translateText(text: text, direction: direction.value);
      switch (result) {
        case Ok(value: final r):
          translatedText.value = r.translatedText;
          lastResult.value = r;
          messages.add(r);
          onTranslated?.call(r);
          if (autoSpeak.value) {
            try {
              await _speakText(text: r.translatedText, language: targetLanguage);
            } catch (e) {
              errorMessage.value = '음성 재생 실패: $e';
            }
          }
        case Err(failure: final f):
          errorMessage.value = f.message;
      }
    } finally {
      isTranslating.value = false;
    }
  }

  Future<void> speakSource() async {
    final text = sourceText.value.trim();
    if (text.isEmpty) return;
    try {
      await _speakText(text: text, language: sourceLanguage);
    } catch (e) {
      errorMessage.value = '음성 재생 실패: $e';
    }
  }

  Future<void> speakTranslation() async {
    if (translatedText.value.isEmpty) return;
    try {
      await _speakText(text: translatedText.value, language: targetLanguage);
    } catch (e) {
      errorMessage.value = '음성 재생 실패: $e';
    }
  }

  void toggleDirection() {
    errorMessage.value = '';
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

  /// Clears the on-screen conversation log (does not touch saved history).
  void clearConversation() {
    messages.clear();
    clear();
  }

  void copyTranslation() {
    if (translatedText.value.isEmpty) return;
    Clipboard.setData(ClipboardData(text: translatedText.value));
  }

  void copyText(String text) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
  }

  /// Replays a logged message's translation in its target language.
  Future<void> speakMessage(TranslationResult message) async {
    if (message.translatedText.isEmpty) return;
    try {
      await _speakText(
        text: message.translatedText,
        language: message.direction.to,
      );
    } catch (e) {
      errorMessage.value = '음성 재생 실패: $e';
    }
  }

  /// Manually warms up the inference engine (from the "워밍업" button) so the
  /// first translation responds quickly. Idempotent: no-op once warmed up or
  /// while a warm-up is already running.
  Future<void> warmUp() async {
    final warmUpModel = _warmUpModel;
    if (warmUpModel == null || isWarmingUp.value || warmedUp.value) return;

    isWarmingUp.value = true;
    errorMessage.value = '';
    try {
      final result = await warmUpModel();
      switch (result) {
        case Ok():
          warmedUp.value = true;
        case Err(failure: final f):
          errorMessage.value = '워밍업 실패: ${f.message}';
      }
    } finally {
      isWarmingUp.value = false;
    }
  }

  Future<void> openAppSettings() => _permission.openSettings();
}
