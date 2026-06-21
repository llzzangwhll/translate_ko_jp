import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/data/services/model_download_service.dart';
import 'package:translate_ko_jp/domain/entities/model_status.dart';
import 'package:translate_ko_jp/domain/usecases/ensure_model_ready.dart';
import 'package:translate_ko_jp/presentation/setup/setup_controller.dart';

import '../../fakes/fake_model_repository.dart';

void main() {
  late FakeModelRepository repo;
  late EnsureModelReady ensure;
  late SetupController controller;
  var navigatedToTranslation = 0;

  SetupController build() => SetupController(
        repository: repo,
        ensureModelReady: ensure,
        onReady: () => navigatedToTranslation++,
      );

  setUp(() {
    navigatedToTranslation = 0;
    repo = FakeModelRepository();
    ensure = EnsureModelReady(repo);
  });

  test('initial status is notDownloaded', () {
    controller = build();
    expect(controller.status.value, ModelStatus.notDownloaded);
    expect(controller.isBusy.value, isFalse);
  });

  test('checkStatus(loaded) navigates to translation immediately', () async {
    repo.statusValue = ModelStatus.loaded;
    controller = build();

    await controller.checkStatus();

    expect(controller.status.value, ModelStatus.loaded);
    expect(navigatedToTranslation, 1);
  });

  test('checkStatus(notDownloaded) stays on setup, no nav', () async {
    repo.statusValue = ModelStatus.notDownloaded;
    controller = build();

    await controller.checkStatus();

    expect(controller.status.value, ModelStatus.notDownloaded);
    expect(navigatedToTranslation, 0);
  });

  test('startDownload streams progress then stops at downloaded (no load/nav)',
      () async {
    repo.statusValue = ModelStatus.notDownloaded;
    repo.downloadScript = const [
      DownloadProgress(received: 50, total: 100, done: false),
      DownloadProgress(received: 100, total: 100, done: true),
    ];
    controller = build();

    await controller.startDownload();

    // progress reflects last received fraction (1.0) on completion.
    expect(controller.receivedBytes.value, 100);
    expect(controller.totalBytes.value, 100);
    // Stops at downloaded so the "다음" button shows; no load, no navigation.
    expect(controller.status.value, ModelStatus.downloaded);
    expect(repo.loadCalled, isFalse);
    expect(navigatedToTranslation, 0);
    expect(controller.isBusy.value, isFalse);
  });

  test('proceed loads the model then navigates', () async {
    repo.loadResult = const Ok(null);
    controller = build();
    controller.status.value = ModelStatus.downloaded;

    await controller.proceed();

    expect(repo.loadCalled, isTrue);
    expect(controller.status.value, ModelStatus.loaded);
    expect(navigatedToTranslation, 1);
    expect(controller.isBusy.value, isFalse);
  });

  test('proceed sets error status when load fails', () async {
    repo.loadResult = const Err(ModelFailureForTest());
    controller = build();
    controller.status.value = ModelStatus.downloaded;

    await controller.proceed();

    expect(controller.status.value, ModelStatus.error);
    expect(controller.errorMessage.value, isNotEmpty);
    expect(navigatedToTranslation, 0);
    expect(controller.isBusy.value, isFalse);
  });

  test('cancel resets busy and status to notDownloaded', () async {
    controller = build();
    controller.isBusy.value = true;
    controller.status.value = ModelStatus.downloading;

    controller.cancel();

    expect(controller.isBusy.value, isFalse);
    expect(controller.status.value, ModelStatus.notDownloaded);
    expect(repo.cancelDownloadCalled, isTrue);
  });
}

// local Failure subtype for the load-failure test.
class ModelFailureForTest extends ModelFailure {
  const ModelFailureForTest() : super('load failed in test');
}
