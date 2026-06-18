import '../../core/language.dart';

abstract interface class TtsService {
  Future<void> initialize();
  Future<void> speak({required String text, required Language language});
  Future<void> stop();
}
