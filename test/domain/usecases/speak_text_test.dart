import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/core/language.dart';
import 'package:translate_ko_jp/domain/usecases/speak_text.dart';
import '../../fakes/fake_tts_service.dart';

void main() {
  test('SpeakText forwards text and language to TtsService', () async {
    final tts = FakeTtsService();
    final useCase = SpeakText(tts);

    await useCase(text: 'こんにちは', language: Language.ja);

    expect(tts.spoken.single.text, 'こんにちは');
    expect(tts.spoken.single.language, Language.ja);
  });
}
