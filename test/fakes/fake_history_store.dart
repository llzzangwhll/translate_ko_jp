import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/data/services/history_store.dart';

class FakeHistoryStore implements HistoryStore {
  final List<TranslationResult> _rows = <TranslationResult>[];
  int _nextId = 1;

  bool throwOnInsert = false;
  bool throwOnGetAll = false;
  bool throwOnDelete = false;
  bool throwOnClear = false;

  @override
  Future<int> insert(TranslationResult result) async {
    if (throwOnInsert) throw Exception('insert failed');
    final id = _nextId++;
    _rows.add(result.copyWith(id: id));
    return id;
  }

  @override
  Future<List<TranslationResult>> getAll() async {
    if (throwOnGetAll) throw Exception('getAll failed');
    final sorted = List<TranslationResult>.from(_rows)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  @override
  Future<void> delete(int id) async {
    if (throwOnDelete) throw Exception('delete failed');
    _rows.removeWhere((r) => r.id == id);
  }

  @override
  Future<void> clear() async {
    if (throwOnClear) throw Exception('clear failed');
    _rows.clear();
  }
}
