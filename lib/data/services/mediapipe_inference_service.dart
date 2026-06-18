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
