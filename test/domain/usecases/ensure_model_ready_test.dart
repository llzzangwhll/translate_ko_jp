import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/domain/entities/model_status.dart';
import 'package:translate_ko_jp/domain/usecases/ensure_model_ready.dart';

import '../../fakes/fake_model_repository.dart';

void main() {
  late FakeModelRepository repo;
  late EnsureModelReady useCase;

  setUp(() {
    repo = FakeModelRepository();
    useCase = EnsureModelReady(repo);
  });

  test('notDownloaded -> needsDownload, does not load', () async {
    repo.statusValue = ModelStatus.notDownloaded;

    final outcome = await useCase();

    expect(outcome, isA<Ok<ModelReadiness>>());
    expect((outcome as Ok<ModelReadiness>).value, ModelReadiness.needsDownload);
    expect(repo.loadCalled, isFalse);
  });

  test('already loaded -> ready, does not call load again', () async {
    repo.statusValue = ModelStatus.loaded;

    final outcome = await useCase();

    expect((outcome as Ok<ModelReadiness>).value, ModelReadiness.ready);
    expect(repo.loadCalled, isFalse);
  });

  test('downloaded but not loaded -> loads then ready', () async {
    repo.statusValue = ModelStatus.downloaded;
    repo.loadResult = const Ok(null);

    final outcome = await useCase();

    expect(repo.loadCalled, isTrue);
    expect((outcome as Ok<ModelReadiness>).value, ModelReadiness.ready);
  });

  test('downloaded but load fails -> propagates Err(ModelFailure)', () async {
    repo.statusValue = ModelStatus.downloaded;
    repo.loadResult = const Err(ModelFailure('boom'));

    final outcome = await useCase();

    expect(outcome, isA<Err<ModelReadiness>>());
    expect((outcome as Err<ModelReadiness>).failure, isA<ModelFailure>());
  });
}
