import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/data/repositories/translation_repository.dart';
import 'package:translate_ko_jp/domain/usecases/listen_speech.dart';
import 'package:translate_ko_jp/domain/usecases/save_translation.dart';
import 'package:translate_ko_jp/domain/usecases/speak_text.dart';
import 'package:translate_ko_jp/domain/usecases/translate_text.dart';
import 'package:translate_ko_jp/presentation/translation/translation_controller.dart';
import '../fakes/fake_inference_service.dart';
import '../fakes/fake_speech_service.dart';
import '../fakes/fake_tts_service.dart';
import '../fakes/fake_history_repository.dart';

void main() {
  test('translation is saved to history via the seam', () async {
    final history = FakeHistoryRepository();
    final repo = TranslationRepositoryImpl(FakeInferenceService(response: 'こんにちは'));
    final controller = TranslationController(
      translateText: TranslateText(repo),
      listenSpeech: ListenSpeech(FakeSpeechService()),
      speakText: SpeakText(FakeTtsService()),
    );
    final save = SaveTranslation(history);
    controller.onTranslated = (r) => save(r);

    controller.sourceText.value = '안녕';
    await controller.translate();
    await Future<void>.delayed(Duration.zero);

    expect(history.savedArgs, hasLength(1));
    expect(history.savedArgs.single.translatedText, 'こんにちは');
  });
}
