import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../core/result.dart';
import '../data/services/ocr_service.dart';
import '../data/services/ocr_service_impl.dart';
import '../data/services/image_picker_service.dart';
import '../data/services/image_picker_service_impl.dart';
import '../data/services/permission_service.dart';
import '../data/services/tts_service.dart';
import '../data/repositories/ocr_repository.dart';
import '../data/repositories/translation_repository.dart';
import '../domain/usecases/pick_image.dart';
import '../domain/usecases/recognize_image_text.dart';
import '../domain/usecases/speak_text.dart';
import '../domain/usecases/translate_text.dart';
import '../domain/usecases/save_translation.dart';
import '../presentation/ocr/ocr_controller.dart';

/// Registers the camera/album OCR translation flow. Runs after translation and
/// history deps: it reuses TranslationRepository, TtsService and SaveTranslation.
void registerOcrDeps() {
  Get.lazyPut<OcrService>(() => OcrServiceImpl(), fenix: true);
  Get.lazyPut<ImagePickerService>(() => ImagePickerServiceImpl(), fenix: true);

  Get.lazyPut<OcrRepository>(
    () => OcrRepositoryImpl(Get.find<OcrService>()),
    fenix: true,
  );

  Get.lazyPut<OcrController>(
    () {
      final controller = OcrController(
        pickImage: PickImage(Get.find<ImagePickerService>()),
        recognizeImageText: RecognizeImageText(Get.find<OcrRepository>()),
        translateText: TranslateText(Get.find<TranslationRepository>()),
        speakText: SpeakText(Get.find<TtsService>()),
        permissionService: Get.find<PermissionService>(),
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
