import '../../domain/entities/language_direction.dart';

abstract interface class InferenceService {
  Future<bool> modelExists();
  Future<bool> isLoaded();
  Future<void> load({String? modelPath});

  /// Runs a tiny throwaway inference to pay the one-time warm-up cost up front
  /// (graph build, GPU shader compile, KV-cache allocation), so the first real
  /// translation is fast. Requires the model to already be loaded.
  Future<void> warmUp();

  Future<String> translate({
    required String text,
    required LanguageDirection direction,
  });
  Future<void> dispose();
}
