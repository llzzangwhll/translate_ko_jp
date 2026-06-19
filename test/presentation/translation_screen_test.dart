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
import '../fakes/fake_permission_service.dart';
import '../fakes/fake_speech_service.dart';
import '../fakes/fake_tts_service.dart';

TranslationController _makeController({
  FakePermissionService? permission,
}) {
  final repo = TranslationRepositoryImpl(FakeInferenceService());
  return TranslationController(
    translateText: TranslateText(repo),
    listenSpeech: ListenSpeech(FakeSpeechService()),
    speakText: SpeakText(FakeTtsService()),
    permissionService: permission ?? FakePermissionService(),
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

  testWidgets('설정 열기 button shown when permissionPermanentlyDenied is true', (tester) async {
    final controller = _makeController();
    Get.put<TranslationController>(controller);

    await tester.pumpWidget(const GetMaterialApp(home: TranslationScreen()));

    // Initially the button should not be shown
    expect(find.text('설정 열기'), findsNothing);

    // Simulate permanent denial
    controller.permissionPermanentlyDenied.value = true;
    await tester.pump();

    expect(find.text('설정 열기'), findsOneWidget);
    Get.reset();
  });
}
