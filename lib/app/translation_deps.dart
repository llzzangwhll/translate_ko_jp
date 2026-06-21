import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../core/result.dart';
import '../data/services/inference_service.dart';
import '../data/services/mediapipe_inference_service.dart';
import '../data/services/permission_service.dart';
import '../data/services/permission_service_impl.dart';
import '../data/services/speech_service.dart';
import '../data/services/speech_service_impl.dart';
import '../data/services/tts_service.dart';
import '../data/services/tts_service_impl.dart';
import '../data/repositories/translation_repository.dart';
import '../domain/usecases/listen_speech.dart';
import '../domain/usecases/speak_text.dart';
import '../domain/usecases/translate_text.dart';
import '../domain/usecases/warm_up_model.dart';
import '../domain/usecases/save_translation.dart';
import '../presentation/translation/translation_controller.dart';

void registerTranslationDeps() {
  // Services (shared singletons)
  Get.lazyPut<InferenceService>(() => MediaPipeInferenceService(), fenix: true);
  Get.lazyPut<SpeechService>(() => SpeechServiceImpl(), fenix: true);
  Get.lazyPut<TtsService>(() => TtsServiceImpl()..initialize(), fenix: true);
  Get.lazyPut<PermissionService>(() => PermissionServiceImpl(), fenix: true);

  // Repository
  Get.lazyPut<TranslationRepository>(
    () => TranslationRepositoryImpl(Get.find<InferenceService>()),
    fenix: true,
  );

  // Controller
  Get.lazyPut<TranslationController>(
    () {
      final controller = TranslationController(
        translateText: TranslateText(Get.find<TranslationRepository>()),
        listenSpeech: ListenSpeech(Get.find<SpeechService>()),
        speakText: SpeakText(Get.find<TtsService>()),
        permissionService: Get.find<PermissionService>(),
        warmUpModel: WarmUpModel(Get.find<TranslationRepository>()),
      );
      final save = Get.find<SaveTranslation>();
      controller.onTranslated = (r) async {
        final res = await save(r);
        if (res is Err<int>) {
          debugPrint('History save failed: ${res.failure.message}');
        }
      };
      return controller;
    },
    fenix: true,
  );
}
