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
