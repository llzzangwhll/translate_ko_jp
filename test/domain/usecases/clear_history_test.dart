import 'package:flutter_test/flutter_test.dart';

import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/domain/usecases/clear_history.dart';

import '../../fakes/fake_history_repository.dart';

void main() {
  late FakeHistoryRepository repo;
  late ClearHistory clearHistory;

  setUp(() {
    repo = FakeHistoryRepository();
    clearHistory = ClearHistory(repo);
  });

  test('delegates to repository.clear', () async {
    final result = await clearHistory();
    expect(result, isA<Ok<void>>());
    expect(repo.clearCount, 1);
  });

  test('propagates Err on failure', () async {
    repo.failClear = const StorageFailure('boom');
    final result = await clearHistory();
    expect((result as Err<void>).failure, isA<StorageFailure>());
  });
}
