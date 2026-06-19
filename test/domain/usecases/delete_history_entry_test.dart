import 'package:flutter_test/flutter_test.dart';

import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/domain/usecases/delete_history_entry.dart';

import '../../fakes/fake_history_repository.dart';

void main() {
  late FakeHistoryRepository repo;
  late DeleteHistoryEntry deleteEntry;

  setUp(() {
    repo = FakeHistoryRepository();
    deleteEntry = DeleteHistoryEntry(repo);
  });

  test('delegates to repository.delete with the id', () async {
    final result = await deleteEntry(42);
    expect(result, isA<Ok<void>>());
    expect(repo.deletedIds, [42]);
  });

  test('propagates Err on failure', () async {
    repo.failDelete = const StorageFailure('boom');
    final result = await deleteEntry(1);
    expect((result as Err<void>).failure, isA<StorageFailure>());
  });
}
