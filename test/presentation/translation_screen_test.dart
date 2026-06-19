import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:translate_ko_jp/data/repositories/translation_repository.dart';
import 'package:translate_ko_jp/domain/usecases/listen_speech.dart';
import 'package:translate_ko_jp/domain/usecases/speak_text.dart';
import 'package:translate_ko_jp/domain/usecases/translate_text.dart';
import 'package:translate_ko_jp/presentation/translation/translation_controller.dart';
import 'package:translate_ko_jp/presentation/translation/translation_screen.dart';
import '../fakes/fake_inference_service.dart';
import '../fakes/fake_speech_service.dart';
import '../fakes/fake_tts_service.dart';

TranslationController _makeController() {
  final repo = TranslationRepositoryImpl(FakeInferenceService());
  return TranslationController(
    translateText: TranslateText(repo),
    listenSpeech: ListenSpeech(FakeSpeechService()),
    speakText: SpeakText(FakeTtsService()),
  );
}

void main() {
  testWidgets('renders source/translated panels and mic button', (tester) async {
    Get.put<TranslationController>(_makeController());

    await tester.pumpWidget(const GetMaterialApp(home: TranslationScreen()));

    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.byType(TranslationScreen), findsOneWidget);
    Get.reset();
  });

  testWidgets('auto-read toggle Switch is present on screen', (tester) async {
    Get.put<TranslationController>(_makeController());

    await tester.pumpWidget(const GetMaterialApp(home: TranslationScreen()));

    expect(find.byType(Switch), findsOneWidget);
    Get.reset();
  });
}
