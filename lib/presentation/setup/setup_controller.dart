import 'dart:async';

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

  double get fraction =>
      totalBytes.value > 0 ? receivedBytes.value / totalBytes.value : 0.0;

  @override
  void onInit() {
    super.onInit();
    unawaited(checkStatus());
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

  /// Downloads the configured model. On success the screen shows an enabled
  /// "다음" button ([ModelStatus.downloaded]); loading into the engine happens
  /// later in [proceed]. Does not navigate.
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
      }
    } catch (e) {
      status.value = ModelStatus.error;
      errorMessage.value = '다운로드 실패: $e';
      isBusy.value = false;
      return;
    }

    status.value = ModelStatus.downloaded;
    isBusy.value = false;
  }

  /// "다음" button: loads the downloaded model into the engine, then navigates
  /// to the translation screen. Shows a busy state while loading.
  Future<void> proceed() async {
    if (isBusy.value) return;
    isBusy.value = true;
    errorMessage.value = '';
    final result = await _repository.load();
    isBusy.value = false;
    switch (result) {
      case Ok():
        status.value = ModelStatus.loaded;
        _onReady();
      case Err(failure: final f):
        status.value = ModelStatus.error;
        errorMessage.value = f.message;
    }
  }

  /// Retries from the right point: if the file is already downloaded (e.g. the
  /// load failed), retry the load via [proceed]; otherwise (re)download,
  /// resuming via the `.part` file when present.
  Future<void> retry() async {
    errorMessage.value = '';
    final s = await _repository.currentStatus();
    if (s == ModelStatus.downloaded || s == ModelStatus.loaded) {
      await proceed();
    } else {
      await startDownload();
    }
  }

  /// Cancels an in-flight download and returns to the idle setup state.
  void cancel() {
    _repository.cancelDownload();
    isBusy.value = false;
    status.value = ModelStatus.notDownloaded;
  }
}
