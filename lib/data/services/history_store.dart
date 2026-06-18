import '../../domain/entities/translation_result.dart';

abstract interface class HistoryStore {
  Future<int> insert(TranslationResult result);
  Future<List<TranslationResult>> getAll();
  Future<void> delete(int id);
  Future<void> clear();
}
