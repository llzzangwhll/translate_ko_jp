import 'package:get/get.dart';

import '../data/repositories/model_repository.dart';
import '../data/services/inference_service.dart';
import '../data/services/model_config.dart';
import '../data/services/model_download_service.dart';
import '../data/services/model_download_service_impl.dart';
import '../domain/usecases/ensure_model_ready.dart';
import '../presentation/setup/setup_controller.dart';
import 'routes.dart';

/// Registers model-management dependencies. Call from AppBinding (plan 05).
///
/// Precondition: an [InferenceService] is already registered in GetX DI
/// (owned by plan 01). This function only looks it up.
///
/// [config] defaults to [ModelConfig.fromEnvironment()], which reads
/// `MODEL_URL`, `MODEL_SHA256`, and `HF_TOKEN` from `--dart-define` values
/// supplied at build/run time. Pass an explicit config in tests.
void registerModelDeps({ModelConfig? config}) {
  final cfg = config ?? ModelConfig.fromEnvironment();

  Get.lazyPut<ModelDownloadService>(() => ModelDownloadServiceImpl(), fenix: true);

  Get.lazyPut<ModelRepository>(
    () => ModelRepositoryImpl(
      inference: Get.find<InferenceService>(),
      downloadService: Get.find<ModelDownloadService>(),
      config: cfg,
    ),
    fenix: true,
  );

  Get.lazyPut<EnsureModelReady>(
    () => EnsureModelReady(Get.find<ModelRepository>()),
    fenix: true,
  );

  Get.lazyPut<SetupController>(
    () => SetupController(
      repository: Get.find<ModelRepository>(),
      ensureModelReady: Get.find<EnsureModelReady>(),
      onReady: () => Get.offAllNamed(Routes.translation),
    ),
    fenix: true,
  );
}
