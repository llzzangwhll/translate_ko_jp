import '../../core/result.dart';
import '../../data/repositories/translation_repository.dart';
import '../entities/language_direction.dart';
import '../entities/translation_result.dart';

class TranslateText {
  final TranslationRepository _repository;
  TranslateText(this._repository);

  Future<Result<TranslationResult>> call({
    required String text,
    required LanguageDirection direction,
  }) {
    return _repository.translate(text: text, direction: direction);
  }
}
