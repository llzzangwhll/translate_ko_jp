import '../../core/language.dart';
import '../../data/services/tts_service.dart';

class SpeakText {
  final TtsService _tts;
  SpeakText(this._tts);

  Future<void> call({required String text, required Language language}) {
    return _tts.speak(text: text, language: language);
  }
}
