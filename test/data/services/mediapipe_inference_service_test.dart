import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/data/services/mediapipe_inference_service.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.translate_ko_jp/gemma');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('translate sends promptLabel langs and returns response', () async {
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return 'こんにちは';
    });

    final service = MediaPipeInferenceService();
    final out = await service.translate(
      text: '안녕하세요',
      direction: LanguageDirection.koToJa(),
    );

    expect(out, 'こんにちは');
    expect(captured!.method, 'translate');
    expect(captured!.arguments['text'], '안녕하세요');
    expect(captured!.arguments['sourceLang'], 'Korean');
    expect(captured!.arguments['targetLang'], 'Japanese');
  });

  test('isLoaded returns channel boolean', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isModelLoaded');
      return true;
    });
    final service = MediaPipeInferenceService();
    expect(await service.isLoaded(), isTrue);
  });

  test('modelExists swallows PlatformException as false', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'X');
    });
    final service = MediaPipeInferenceService();
    expect(await service.modelExists(), isFalse);
  });
}
