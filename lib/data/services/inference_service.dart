import '../../domain/entities/language_direction.dart';

abstract interface class InferenceService {
  Future<bool> modelExists();
  Future<bool> isLoaded();
  Future<void> load({String? modelPath});
  Future<String> translate({
    required String text,
    required LanguageDirection direction,
  });
  Future<void> dispose();
}
