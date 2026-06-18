import 'package:get/get.dart';
import '../data/services/inference_service.dart';
import '../data/services/mediapipe_inference_service.dart';
import '../data/services/speech_service.dart';
import '../data/services/speech_service_impl.dart';
import '../data/services/tts_service.dart';
import '../data/services/tts_service_impl.dart';
import '../data/repositories/translation_repository.dart';
import '../domain/usecases/listen_speech.dart';
import '../domain/usecases/speak_text.dart';
import '../domain/usecases/translate_text.dart';
import '../presentation/translation/translation_controller.dart';

void registerTranslationDeps() {
  // Services (shared singletons)
  Get.lazyPut<InferenceService>(() => MediaPipeInferenceService(), fenix: true);
  Get.lazyPut<SpeechService>(() => SpeechServiceImpl()..initialize(), fenix: true);
  Get.lazyPut<TtsService>(() => TtsServiceImpl()..initialize(), fenix: true);

  // Repository
  Get.lazyPut<TranslationRepository>(
    () => TranslationRepositoryImpl(Get.find<InferenceService>()),
    fenix: true,
  );

  // Controller
  Get.lazyPut<TranslationController>(
    () => TranslationController(
      translateText: TranslateText(Get.find<TranslationRepository>()),
      listenSpeech: ListenSpeech(Get.find<SpeechService>()),
      speakText: SpeakText(Get.find<TtsService>()),
    ),
    fenix: true,
  );
}
