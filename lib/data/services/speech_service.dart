import '../../core/language.dart';

class SpeechResult {
  final String text;
  final bool isFinal;
  const SpeechResult(this.text, this.isFinal);
}

abstract interface class SpeechService {
  Future<bool> initialize();
  bool get isAvailable;
  Future<void> listen({
    required Language language,
    required void Function(SpeechResult result) onResult,
  });
  Future<void> stop();
  Future<void> cancel();
}
