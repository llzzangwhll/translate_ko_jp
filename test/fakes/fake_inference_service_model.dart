import 'package:translate_ko_jp/data/services/inference_service.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';

/// Self-contained fake of [InferenceService] for the model-management flow.
///
/// Named with a `Model` suffix so it never collides with plan 01's
/// `FakeInferenceService` in `test/fakes/fake_inference_service.dart`.
class FakeInferenceServiceModel implements InferenceService {
  bool existsValue = false;
  bool loadedValue = false;

  /// If non-null, [load] throws this object.
  Object? throwOnLoad;

  bool loadCalled = false;
  String? lastModelPath;

  @override
  Future<bool> modelExists() async => existsValue;

  @override
  Future<bool> isLoaded() async => loadedValue;

  @override
  Future<void> load({String? modelPath}) async {
    loadCalled = true;
    lastModelPath = modelPath;
    if (throwOnLoad != null) {
      throw throwOnLoad!;
    }
    loadedValue = true;
  }

  @override
  Future<String> translate({
    required String text,
    required LanguageDirection direction,
  }) async =>
      text;

  @override
  Future<void> dispose() async {}
}
