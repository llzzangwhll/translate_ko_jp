import '../../core/result.dart';
import '../entities/translation_result.dart';
import '../../data/repositories/history_repository.dart';

class SaveTranslation {
  final HistoryRepository _repository;
  const SaveTranslation(this._repository);

  Future<Result<int>> call(TranslationResult result) {
    return _repository.save(result);
  }
}
