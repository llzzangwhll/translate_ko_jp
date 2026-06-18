import 'dart:async';

import 'package:path_provider/path_provider.dart';

import '../../core/failure.dart';
import '../../core/result.dart';
import '../../domain/entities/model_status.dart';
import '../services/inference_service.dart';
import '../services/model_config.dart';
import '../services/model_download_service.dart';

/// Contract (matches shared contracts in INDEX). If plan 00 already declares
/// this interface in this file, keep ONE copy and delete the duplicate.
abstract interface class ModelRepository {
  Future<ModelStatus> currentStatus();
  Stream<DownloadProgress> download(); // uses configured URL/checksum
  Future<Result<void>> load();
  void cancelDownload();
}

/// Resolves the on-disk destination path for [fileName]. Injectable so tests
/// avoid path_provider's platform channel.
typedef ResolveDestPath = Future<String> Function(String fileName);

Future<String> _defaultResolveDestPath(String fileName) async {
  final dir = await getApplicationDocumentsDirectory();
  return '${dir.path}/$fileName';
}

class ModelRepositoryImpl implements ModelRepository {
  final InferenceService _inference;
  final ModelDownloadService _downloadService;
  final ModelConfig _config;
  final ResolveDestPath _resolveDestPath;

  ModelRepositoryImpl({
    required InferenceService inference,
    required ModelDownloadService downloadService,
    required ModelConfig config,
    ResolveDestPath resolveDestPath = _defaultResolveDestPath,
  })  : _inference = inference,
        _downloadService = downloadService,
        _config = config,
        _resolveDestPath = resolveDestPath;

  @override
  Future<ModelStatus> currentStatus() async {
    if (await _inference.isLoaded()) return ModelStatus.loaded;
    if (await _inference.modelExists()) return ModelStatus.downloaded;
    return ModelStatus.notDownloaded;
  }

  @override
  Stream<DownloadProgress> download() async* {
    final destPath = await _resolveDestPath(_config.fileName);
    yield* _downloadService.download(
      url: _config.url,
      destPath: destPath,
      sha256: _config.sha256,
      headers: _config.headers,
    );
  }

  /// Forwards cancellation to the underlying download service.
  @override
  void cancelDownload() => _downloadService.cancel();

  @override
  Future<Result<void>> load() async {
    try {
      final destPath = await _resolveDestPath(_config.fileName);
      await _inference.load(modelPath: destPath);
      return const Ok(null);
    } catch (e) {
      return Err(ModelFailure('모델 로드 실패: $e'));
    }
  }
}
