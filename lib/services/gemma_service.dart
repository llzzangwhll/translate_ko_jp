import 'package:flutter/services.dart';
import 'package:get/get.dart';

class GemmaService extends GetxService {
  static const _channel = MethodChannel('com.example.translate_ko_jp/gemma');

  Future<bool> checkModelExists() async {
    try {
      final result = await _channel.invokeMethod('checkModelExists');
      return result == true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> isModelLoaded() async {
    try {
      final result = await _channel.invokeMethod('isModelLoaded');
      return result == true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> loadModel({String? modelPath}) async {
    final args = modelPath != null ? {'modelPath': modelPath} : null;
    final result = await _channel.invokeMethod('loadModel', args);
    return result == true;
  }

  Future<String> translate({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final result = await _channel.invokeMethod('translate', {
      'text': text,
      'sourceLang': sourceLang,
      'targetLang': targetLang,
    });
    return result ?? '';
  }
}
