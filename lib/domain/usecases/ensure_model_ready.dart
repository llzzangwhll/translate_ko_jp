import '../../core/result.dart';
import '../../data/repositories/model_repository.dart';
import '../entities/model_status.dart';

/// Outcome of an [EnsureModelReady] check.
enum ModelReadiness {
  /// Model file is absent; the setup screen must trigger a download.
  needsDownload,

  /// Model is downloaded and loaded into the inference engine.
  ready,
}

/// Checks model status and, if the file already exists, loads it.
/// Returns whether a download is still required, or that the model is ready.
class EnsureModelReady {
  final ModelRepository _repo;
  const EnsureModelReady(this._repo);

  Future<Result<ModelReadiness>> call() async {
    final status = await _repo.currentStatus();
    switch (status) {
      case ModelStatus.loaded:
        return const Ok(ModelReadiness.ready);
      case ModelStatus.notDownloaded:
      case ModelStatus.error:
        return const Ok(ModelReadiness.needsDownload);
      case ModelStatus.downloading:
      case ModelStatus.downloaded:
        final loadResult = await _repo.load();
        return switch (loadResult) {
          Ok() => const Ok(ModelReadiness.ready),
          Err(failure: final f) => Err(f),
        };
    }
  }
}
