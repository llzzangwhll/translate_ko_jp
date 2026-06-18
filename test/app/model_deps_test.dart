import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:translate_ko_jp/app/model_deps.dart';
import 'package:translate_ko_jp/data/repositories/model_repository.dart';
import 'package:translate_ko_jp/data/services/inference_service.dart';
import 'package:translate_ko_jp/domain/usecases/ensure_model_ready.dart';
import 'package:translate_ko_jp/presentation/setup/setup_controller.dart';

import '../fakes/fake_inference_service_model.dart';

void main() {
  setUp(() => Get.reset());
  tearDown(() => Get.reset());

  test('registers repository, use case, and controller', () {
    // InferenceService is owned/registered by plan 01; provide a fake here.
    Get.put<InferenceService>(FakeInferenceServiceModel());

    registerModelDeps();

    expect(Get.find<ModelRepository>(), isA<ModelRepository>());
    expect(Get.find<EnsureModelReady>(), isA<EnsureModelReady>());
    expect(Get.find<SetupController>(), isA<SetupController>());
  });
}
