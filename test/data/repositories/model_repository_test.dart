import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/data/repositories/model_repository.dart';
import 'package:translate_ko_jp/data/services/model_config.dart';
import 'package:translate_ko_jp/data/services/model_download_service.dart';
import 'package:translate_ko_jp/domain/entities/model_status.dart';

import '../../fakes/fake_inference_service_model.dart';
import '../../fakes/fake_model_download_service.dart';

void main() {
  late FakeInferenceServiceModel inference;
  late FakeModelDownloadService downloader;
  late ModelRepositoryImpl repo;

  setUp(() {
    inference = FakeInferenceServiceModel();
    downloader = FakeModelDownloadService();
    repo = ModelRepositoryImpl(
      inference: inference,
      downloadService: downloader,
      config: const ModelConfig(
        url: 'https://example.com/m.task',
        fileName: 'm.task',
        sha256: 'abc',
      ),
      resolveDestPath: (fileName) async => '/tmp/$fileName',
    );
  });

  group('currentStatus', () {
    test('loaded when isLoaded true', () async {
      inference.existsValue = true;
      inference.loadedValue = true;
      expect(await repo.currentStatus(), ModelStatus.loaded);
    });

    test('downloaded when exists but not loaded', () async {
      inference.existsValue = true;
      inference.loadedValue = false;
      expect(await repo.currentStatus(), ModelStatus.downloaded);
    });

    test('notDownloaded when model does not exist', () async {
      inference.existsValue = false;
      inference.loadedValue = false;
      expect(await repo.currentStatus(), ModelStatus.notDownloaded);
    });
  });

  group('download', () {
    test('delegates with configured url, destPath and checksum', () async {
      downloader.script = const [
        DownloadProgress(received: 5, total: 10, done: false),
        DownloadProgress(received: 10, total: 10, done: true),
      ];

      final events = await repo.download().toList();

      expect(downloader.lastUrl, 'https://example.com/m.task');
      expect(downloader.lastDestPath, '/tmp/m.task');
      expect(downloader.lastSha256, 'abc');
      expect(events.last.done, isTrue);
    });

    test('passes config headers through', () async {
      repo = ModelRepositoryImpl(
        inference: inference,
        downloadService: downloader,
        config: const ModelConfig(
          url: 'https://example.com/m.task',
          fileName: 'm.task',
          headers: {'Authorization': 'Bearer x'},
        ),
        resolveDestPath: (fileName) async => '/tmp/$fileName',
      );
      downloader.script = const [
        DownloadProgress(received: 1, total: 1, done: true),
      ];

      await repo.download().toList();

      expect(downloader.lastHeaders, {'Authorization': 'Bearer x'});
    });
  });

  group('load', () {
    test('returns Ok when load succeeds', () async {
      final result = await repo.load();
      expect(result, isA<Ok<void>>());
      expect(inference.loadCalled, isTrue);
    });

    test('passes resolved model path to inference.load', () async {
      await repo.load();
      expect(inference.lastModelPath, '/tmp/m.task');
    });

    test('returns Err(ModelFailure) when load throws', () async {
      inference.throwOnLoad = Exception('bad model');
      final result = await repo.load();
      expect(result, isA<Err<void>>());
      final failure = (result as Err<void>).failure;
      expect(failure, isA<ModelFailure>());
      expect(failure.message, contains('bad model'));
    });
  });

  test('cancelDownload delegates to service', () {
    repo.cancelDownload();
    expect(downloader.cancelCalled, isTrue);
  });
}
