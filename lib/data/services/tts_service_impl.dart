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
