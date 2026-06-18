import 'package:get/get.dart';

import '../../core/result.dart';
import '../../data/repositories/model_repository.dart';
import '../../domain/entities/model_status.dart';
import '../../domain/usecases/ensure_model_ready.dart';

/// ViewModel for the model setup screen. Observes [ModelStatus], drives the
/// download (progress / cancel), then loads and navigates to translation.
class SetupController extends GetxController {
  final ModelRepository _repository;
  final EnsureModelReady _ensureModelReady;

  /// Side-effect-free navigation hook; the screen wires this to
  /// `Get.offAllNamed(Routes.translation)`.
  final void Function() _onReady;

  SetupController({
    required ModelRepository repository,
    required EnsureModelReady ensureModelReady,
    required void Function() onReady,
  })  : _repository = repository,
        _ensureModelReady = ensureModelReady,
        _onReady = onReady;

  final status = ModelStatus.notDownloaded.obs;
  final isBusy = false.obs;
  final receivedBytes = 0.obs;
  final totalBytes = 0.obs;
  final errorMessage = ''.obs;

  /// 0.0..1.0 download fraction for the progress bar.
  late final progress = Rx<double>(0.0);

  double get fraction =>
      totalBytes.value > 0 ? receivedBytes.value / totalBytes.value : 0.0;

  @override
  void onInit() {
    super.onInit();
    checkStatus();
  }

  /// Runs EnsureModelReady. If ready, navigates. Otherwise leaves the screen
  /// in a state where the user can trigger a download.
  Future<void> checkStatus() async {
    errorMessage.value = '';
    final statusAtStart = status.value;
    final outcome = await _ensureModelReady();
    // If status or busy changed while we awaited (e.g. startDownload was
    // called, or the UI pre-set a state for testing), don't override it.
    if (isBusy.value || status.value != statusAtStart) return;
    switch (outcome) {
      case Ok(value: final readiness):
        switch (readiness) {
          case ModelReadiness.ready:
            status.value = ModelStatus.loaded;
            _onReady();
          case ModelReadiness.needsDownload:
            final s = await _repository.currentStatus();
            if (!isBusy.value && status.value == statusAtStart) {
              status.value = s;
            }
        }
      case Err(failure: final f):
        if (!isBusy.value && status.value == statusAtStart) {
          status.value = ModelStatus.error;
          errorMessage.value = f.message;
        }
    }
  }

  /// Downloads the configured model, verifies/loads it, then navigates.
  Future<void> startDownload() async {
    isBusy.value = true;
    errorMessage.value = '';
    status.value = ModelStatus.downloading;
    receivedBytes.value = 0;
    totalBytes.value = 0;

    try {
      await for (final p in _repository.download()) {
        receivedBytes.value = p.received;
        totalBytes.value = p.total;
        progress.value = p.fraction;
      }
    } catch (e) {
      status.value = ModelStatus.error;
      errorMessage.value = '다운로드 실패: $e';
      isBusy.value = false;
      return;
    }

    status.value = ModelStatus.downloaded;
    await _loadAndNavigate();
    isBusy.value = false;
  }

  Future<void> _loadAndNavigate() async {
    final result = await _repository.load();
    switch (result) {
      case Ok():
        status.value = ModelStatus.loaded;
        _onReady();
      case Err(failure: final f):
        status.value = ModelStatus.error;
        errorMessage.value = f.message;
    }
  }

  /// Retries from the current point: re-checks status (resumes via .part).
  Future<void> retry() async {
    await startDownload();
  }

  /// Cancels an in-flight download and returns to the idle setup state.
  void cancel() {
    if (_repository case final ModelRepositoryImpl impl) {
      impl.cancelDownload();
    }
    isBusy.value = false;
    status.value = ModelStatus.notDownloaded;
  }
}
