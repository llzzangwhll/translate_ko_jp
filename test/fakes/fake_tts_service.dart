import 'package:translate_ko_jp/core/language.dart';
import 'package:translate_ko_jp/data/services/tts_service.dart';

class FakeTtsService implements TtsService {
  final List<({String text, Language language})> spoken = [];
  bool stopped = false;

  /// If set, [speak] will throw this object instead of recording the call.
  Object? throwOnSpeak;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> speak({required String text, required Language language}) async {
    if (throwOnSpeak != null) throw throwOnSpeak!;
    spoken.add((text: text, language: language));
  }

  @override
  Future<void> stop() async => stopped = true;
}
