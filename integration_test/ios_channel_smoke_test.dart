import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.translate_ko_jp/gemma');
  final log = <MethodCall>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      switch (call.method) {
        case 'isModelLoaded':
          return false; // 로드 전 false (계약)
        case 'checkModelExists':
          return false; // 모델 미배치 false (계약)
        case 'loadModel':
          return true;
        case 'translate':
          return 'こんにちは';
        default:
          return null;
      }
    });
    log.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('isModelLoaded returns false before load (contract)', () async {
    final loaded = await channel.invokeMethod<bool>('isModelLoaded');
    expect(loaded, isFalse);
    expect(log.single.method, 'isModelLoaded');
  });

  test('translate passes Korean/Japanese promptLabels (contract)', () async {
    final out = await channel.invokeMethod<String>('translate', {
      'text': '안녕하세요',
      'sourceLang': 'Korean',
      'targetLang': 'Japanese',
    });
    expect(out, isA<String>());
    final args = log.single.arguments as Map;
    expect(args['sourceLang'], 'Korean');
    expect(args['targetLang'], 'Japanese');
  });
}
