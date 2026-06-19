import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/data/repositories/history_repository.dart';

class FakeHistoryRepository implements HistoryRepository {
  final List<TranslationResult> entries = <TranslationResult>[];
  int _nextId = 1;

  final List<TranslationResult> savedArgs = <TranslationResult>[];
  final List<int> deletedIds = <int>[];
  int clearCount = 0;

  Failure? failSave;
  Failure? failGetAll;
  Failure? failDelete;
  Failure? failClear;

  @override
  Future<Result<int>> save(TranslationResult result) async {
    savedArgs.add(result);
    if (failSave != null) return Err(failSave!);
    final id = _nextId++;
    entries.add(result.copyWith(id: id));
    return Ok(id);
  }

  @override
  Future<Result<List<TranslationResult>>> getAll() async {
    if (failGetAll != null) return Err(failGetAll!);
    final sorted = List<TranslationResult>.from(entries)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Ok(sorted);
  }

  @override
  Future<Result<void>> delete(int id) async {
    deletedIds.add(id);
    if (failDelete != null) return Err(failDelete!);
    entries.removeWhere((e) => e.id == id);
    return const Ok(null);
  }

  @override
  Future<Result<void>> clear() async {
    clearCount++;
    if (failClear != null) return Err(failClear!);
    entries.clear();
    return const Ok(null);
  }
}
