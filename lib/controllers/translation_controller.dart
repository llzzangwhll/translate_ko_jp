import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/gemma_service.dart';

class TranslationController extends GetxController {
  final _gemma = Get.find<GemmaService>();
  final _speech = SpeechToText();
  final _tts = FlutterTts();

  final textController = TextEditingController();

  final isKoToJp = true.obs;
  final isListening = false.obs;
  final isTranslating = false.obs;
  final isModelLoaded = false.obs;
  final isLoadingModel = false.obs;
  final translatedText = ''.obs;
  final statusMessage = '초기화 중...'.obs;

  bool _speechAvailable = false;

  String get sourceLanguage => isKoToJp.value ? '한국어' : '日本語';
  String get targetLanguage => isKoToJp.value ? '日本語' : '한국어';
  String get _sourceLocale => isKoToJp.value ? 'ko_KR' : 'ja_JP';

  @override
  void onInit() {
    super.onInit();
    _init();
  }

  @override
  void onClose() {
    textController.dispose();
    _speech.cancel();
    _tts.stop();
    super.onClose();
  }

  Future<void> _init() async {
    await _initSpeech();
    await _initTts();
    await loadModel();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (error) => isListening.value = false,
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          isListening.value = false;
        }
      },
    );
  }

  Future<void> _initTts() async {
    await _tts.setVolume(1.0);
    await _tts.setSpeechRate(0.45);
  }

  Future<void> loadModel() async {
    try {
      final loaded = await _gemma.isModelLoaded();
      if (loaded) {
        isModelLoaded.value = true;
        statusMessage.value = '준비 완료';
        return;
      }
    } catch (_) {}

    isLoadingModel.value = true;
    statusMessage.value = '모델 로딩 중...';

    try {
      final result = await _gemma.loadModel();
      isModelLoaded.value = result;
      isLoadingModel.value = false;
      statusMessage.value = result ? '준비 완료' : '모델 로딩 실패';
    } catch (e) {
      isLoadingModel.value = false;
      statusMessage.value = e.toString();
    }
  }

  Future<void> toggleListening() async {
    if (isListening.value) {
      await _speech.stop();
      isListening.value = false;
      if (textController.text.isNotEmpty) translate();
      return;
    }

    if (!_speechAvailable) {
      Get.snackbar('오류', '음성 인식을 사용할 수 없습니다',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    isListening.value = true;
    translatedText.value = '';

    await _speech.listen(
      onResult: (result) {
        textController.text = result.recognizedWords;
        textController.selection = TextSelection.fromPosition(
          TextPosition(offset: textController.text.length),
        );
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          translate();
        }
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        localeId: _sourceLocale,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> translate() async {
    final text = textController.text.trim();
    if (text.isEmpty) return;

    if (!isModelLoaded.value) {
      Get.snackbar('오류', '모델이 아직 로드되지 않았습니다',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    isTranslating.value = true;
    translatedText.value = '';

    try {
      final result = await _gemma.translate(
        text: text,
        sourceLang: isKoToJp.value ? 'Korean' : 'Japanese',
        targetLang: isKoToJp.value ? 'Japanese' : 'Korean',
      );
      translatedText.value = result;
    } on PlatformException catch (e) {
      Get.snackbar('번역 실패', e.message ?? '', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isTranslating.value = false;
    }
  }

  Future<void> speakSource() async {
    final text = textController.text.trim();
    if (text.isEmpty) return;
    await _tts.setLanguage(isKoToJp.value ? 'ko-KR' : 'ja-JP');
    await _tts.speak(text);
  }

  Future<void> speakTranslation() async {
    if (translatedText.value.isEmpty) return;
    await _tts.setLanguage(isKoToJp.value ? 'ja-JP' : 'ko-KR');
    await _tts.speak(translatedText.value);
  }

  void toggleDirection() {
    isKoToJp.value = !isKoToJp.value;
    final oldSource = textController.text;
    textController.text = translatedText.value;
    translatedText.value = oldSource;
  }

  void clear() {
    textController.clear();
    translatedText.value = '';
  }

  void copyTranslation() {
    Clipboard.setData(ClipboardData(text: translatedText.value));
    Get.snackbar('복사', '복사되었습니다',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 1));
  }
}
