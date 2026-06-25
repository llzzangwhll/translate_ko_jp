import '../../core/language.dart';

/// On-device OCR: extracts text from an image file using the script recognizer
/// that matches the source [Language].
abstract interface class OcrService {
  Future<String> recognize({
    required String imagePath,
    required Language language,
  });

  /// Releases native recognizer resources.
  Future<void> dispose();
}
