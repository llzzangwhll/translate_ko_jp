import '../../core/result.dart';
import '../entities/translation_result.dart';
import '../../data/repositories/history_repository.dart';

class GetHistory {
  final HistoryRepository _repository;
  const GetHistory(this._repository);

  Future<Result<List<TranslationResult>>> call() {
    return _repository.getAll();
  }
}
