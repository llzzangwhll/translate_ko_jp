import '../../core/result.dart';
import '../../data/repositories/history_repository.dart';

class DeleteHistoryEntry {
  final HistoryRepository _repository;
  const DeleteHistoryEntry(this._repository);

  Future<Result<void>> call(int id) {
    return _repository.delete(id);
  }
}
