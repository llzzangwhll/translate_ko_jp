import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../core/language.dart';
import 'speech_service.dart';

class SpeechServiceImpl implements SpeechService {
  final stt.SpeechToText _speech;
  bool _available = false;

  SpeechServiceImpl({stt.SpeechToText? engine})
      : _speech = engine ?? stt.SpeechToText();

  @override
  Future<bool> initialize() async {
    _available = await _speech.initialize(
      onError: (_) {},
      onStatus: (_) {},
    );
    return _available;
  }

  @override
  bool get isAvailable => _available;

  @override
  Future<void> listen({
    required Language language,
    required void Function(SpeechResult result) onResult,
  }) async {
    await _speech.listen(
      onResult: (r) => onResult(SpeechResult(r.recognizedWords, r.finalResult)),
      listenOptions: stt.SpeechListenOptions(
        localeId: language.sttLocale,
        listenMode: stt.ListenMode.dictation,
        cancelOnError: true,
        partialResults: true,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}
