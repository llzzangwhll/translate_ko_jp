import '../../core/result.dart';
import '../../data/repositories/history_repository.dart';

class ClearHistory {
  final HistoryRepository _repository;
  const ClearHistory(this._repository);

  Future<Result<void>> call() {
    return _repository.clear();
  }
}
