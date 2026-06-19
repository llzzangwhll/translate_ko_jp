import '../../core/failure.dart';
import '../../core/result.dart';
import '../../domain/entities/translation_result.dart';
import '../services/history_store.dart';

abstract interface class HistoryRepository {
  Future<Result<int>> save(TranslationResult result);
  Future<Result<List<TranslationResult>>> getAll();
  Future<Result<void>> delete(int id);
  Future<Result<void>> clear();
}

class HistoryRepositoryImpl implements HistoryRepository {
  final HistoryStore _store;
  const HistoryRepositoryImpl(this._store);

  @override
  Future<Result<int>> save(TranslationResult result) async {
    try {
      final id = await _store.insert(result);
      return Ok(id);
    } catch (e) {
      return Err(StorageFailure('히스토리 저장에 실패했습니다: $e'));
    }
  }

  @override
  Future<Result<List<TranslationResult>>> getAll() async {
    try {
      final list = await _store.getAll();
      return Ok(list);
    } catch (e) {
      return Err(StorageFailure('히스토리 조회에 실패했습니다: $e'));
    }
  }

  @override
  Future<Result<void>> delete(int id) async {
    try {
      await _store.delete(id);
      return const Ok(null);
    } catch (e) {
      return Err(StorageFailure('히스토리 삭제에 실패했습니다: $e'));
    }
  }

  @override
  Future<Result<void>> clear() async {
    try {
      await _store.clear();
      return const Ok(null);
    } catch (e) {
      return Err(StorageFailure('히스토리 전체 삭제에 실패했습니다: $e'));
    }
  }
}
