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
