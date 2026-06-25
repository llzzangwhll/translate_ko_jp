import 'dart:async';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../core/failure.dart';
import '../../core/language.dart';
import '../../core/result.dart';
import '../../domain/entities/language_direction.dart';
import '../../domain/entities/translation_result.dart';
import '../../domain/usecases/pick_image.dart';
import '../../domain/usecases/recognize_image_text.dart';
import '../../domain/usecases/speak_text.dart';
import '../../domain/usecases/translate_text.dart';
import '../../data/services/permission_service.dart';

/// Camera/album OCR → translation flow.
///
/// The user picks a photo (camera or gallery), the source-language text is
/// recognized on-device, and the result is translated immediately, reusing the
/// existing translation/TTS/history pipeline.
class OcrController extends GetxController {
  final PickImage _pickImage;
  final RecognizeImageText _recognizeImageText;
  final TranslateText _translateText;
  final SpeakText _speakText;
  final PermissionService _permission;

  OcrController({
    required PickImage pickImage,
    required RecognizeImageText recognizeImageText,
    required TranslateText translateText,
    required SpeakText speakText,
    required PermissionService permissionService,
  })  : _pickImage = pickImage,
        _recognizeImageText = recognizeImageText,
        _translateText = translateText,
        _speakText = speakText,
        _permission = permissionService;

  // Default to Japanese→Korean: reading Japanese signs/menus is the main use.
  final direction = LanguageDirection.jaToKo().obs;
  final imagePath = Rxn<String>();
  final recognizedText = ''.obs;
  final translatedText = ''.obs;
  final isProcessing = false.obs;
  final autoSpeak = true.obs;
  final errorMessage = ''.obs;
  final permissionPermanentlyDenied = false.obs;

  /// Persists each successful translation to history (wired in ocr_deps).
  void Function(TranslationResult result)? onTranslated;

  Language get sourceLanguage => direction.value.from;
  Language get targetLanguage => direction.value.to;

  void toggleDirection() {
    if (isProcessing.value) return;
    errorMessage.value = '';
    direction.value = direction.value.reversed;
    // Recognized text was in the previous source language; clear stale results.
    recognizedText.value = '';
    translatedText.value = '';
  }

  Future<void> captureFromCamera() async {
    final perm = await _permission.ensureCamera();
    switch (perm) {
      case PermissionResult.granted:
        permissionPermanentlyDenied.value = false;
        errorMessage.value = '';
      case PermissionResult.denied:
        errorMessage.value =
            const PermissionFailure('카메라 권한이 필요합니다. 권한을 허용해 주세요.').message;
        return;
      case PermissionResult.permanentlyDenied:
        permissionPermanentlyDenied.value = true;
        errorMessage.value =
            const PermissionFailure('카메라 권한이 거부되었습니다. 설정에서 허용해 주세요.').message;
        return;
    }
    await _process(() => _pickImage.fromCamera());
  }

  Future<void> pickFromGallery() async {
    await _process(() => _pickImage.fromGallery());
  }

  /// Shared pipeline: pick → recognize → translate. [pick] supplies the image
  /// path (camera or gallery).
  Future<void> _process(Future<String?> Function() pick) async {
    if (isProcessing.value) return;
    isProcessing.value = true;
    try {
      errorMessage.value = '';
      final path = await pick();
      if (path == null) return; // user cancelled
      imagePath.value = path;
      recognizedText.value = '';
      translatedText.value = '';

      final ocr = await _recognizeImageText(
        imagePath: path,
        direction: direction.value,
      );
      final String source;
      switch (ocr) {
        case Ok(value: final text):
          source = text;
          recognizedText.value = text;
        case Err(failure: final f):
          errorMessage.value = f.message;
          return;
      }

      final translation =
          await _translateText(text: source, direction: direction.value);
      switch (translation) {
        case Ok(value: final r):
          translatedText.value = r.translatedText;
          onTranslated?.call(r);
          if (autoSpeak.value) {
            try {
              await _speakText(text: r.translatedText, language: targetLanguage);
            } catch (e) {
              errorMessage.value = '음성 재생 실패: $e';
            }
          }
        case Err(failure: final f):
          errorMessage.value = f.message;
      }
    } on PlatformException catch (e) {
      errorMessage.value = e.message ?? '이미지를 처리하지 못했습니다';
    } catch (e) {
      errorMessage.value = e.toString();
    } finally {
      isProcessing.value = false;
    }
  }

  Future<void> speakTranslation() async {
    if (translatedText.value.isEmpty) return;
    try {
      await _speakText(text: translatedText.value, language: targetLanguage);
    } catch (e) {
      errorMessage.value = '음성 재생 실패: $e';
    }
  }

  void copyText(String text) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> openAppSettings() => _permission.openSettings();
}
