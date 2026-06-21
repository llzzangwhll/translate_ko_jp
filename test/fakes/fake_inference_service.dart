import 'package:translate_ko_jp/data/services/inference_service.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';

class FakeInferenceService implements InferenceService {
  bool exists;
  bool loaded;
  String response;
  Object? throwOnTranslate;
  String? lastText;
  LanguageDirection? lastDirection;

  FakeInferenceService({
    this.exists = true,
    this.loaded = true,
    this.response = 'こんにちは',
    this.throwOnTranslate,
  });

  @override
  Future<bool> modelExists() async => exists;

  @override
  Future<bool> isLoaded() async => loaded;

  @override
  Future<void> load({String? modelPath}) async => loaded = true;

  bool warmUpCalled = false;

  @override
  Future<void> warmUp() async => warmUpCalled = true;

  String backend = 'gpu';

  @override
  Future<String> activeBackend() async => backend;

  @override
  Future<String> translate({
    required String text,
    required LanguageDirection direction,
  }) async {
    lastText = text;
    lastDirection = direction;
    if (throwOnTranslate != null) throw throwOnTranslate!;
    return response;
  }

  @override
  Future<void> dispose() async {}
}
