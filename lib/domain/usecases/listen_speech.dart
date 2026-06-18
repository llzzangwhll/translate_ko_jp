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
