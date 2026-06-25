import '../../core/result.dart';
import '../../data/repositories/ocr_repository.dart';
import '../entities/language_direction.dart';

class RecognizeImageText {
  final OcrRepository _repository;
  RecognizeImageText(this._repository);

  Future<Result<String>> call({
    required String imagePath,
    required LanguageDirection direction,
  }) {
    return _repository.recognizeText(imagePath: imagePath, direction: direction);
  }
}
