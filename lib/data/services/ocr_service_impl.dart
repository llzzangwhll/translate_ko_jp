import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../core/language.dart';
import 'ocr_service.dart';

/// ML Kit on-device text recognition. The Korean and Japanese script models are
/// bundled into the app, so recognition runs fully offline (no network needed).
class OcrServiceImpl implements OcrService {
  /// One recognizer per script, created lazily and reused across calls.
  final Map<TextRecognitionScript, TextRecognizer> _recognizers = {};

  TextRecognizer _recognizerFor(Language language) {
    final script = language == Language.ko
        ? TextRecognitionScript.korean
        : TextRecognitionScript.japanese;
    return _recognizers.putIfAbsent(
      script,
      () => TextRecognizer(script: script),
    );
  }

  @override
  Future<String> recognize({
    required String imagePath,
    required Language language,
  }) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final result = await _recognizerFor(language).processImage(inputImage);
    return result.text;
  }

  @override
  Future<void> dispose() async {
    for (final recognizer in _recognizers.values) {
      await recognizer.close();
    }
    _recognizers.clear();
  }
}
