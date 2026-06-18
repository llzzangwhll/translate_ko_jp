import 'package:flutter/services.dart';
import '../../core/result.dart';
import '../../core/failure.dart';
import '../../domain/entities/language_direction.dart';
import '../../domain/entities/translation_result.dart';
import '../services/inference_service.dart';

abstract interface class TranslationRepository {
  Future<Result<TranslationResult>> translate({
    required String text,
    required LanguageDirection direction,
  });
}

class TranslationRepositoryImpl implements TranslationRepository {
  final InferenceService _inference;
  TranslationRepositoryImpl(this._inference);

  @override
  Future<Result<TranslationResult>> translate({
    required String text,
    required LanguageDirection direction,
  }) async {
    try {
      final raw = await _inference.translate(text: text, direction: direction);
      final translated = raw.trim();
      if (translated.isEmpty) {
        return const Err(InferenceFailure('번역 결과가 비어 있습니다'));
      }
      return Ok(TranslationResult(
        sourceText: text,
        translatedText: translated,
        direction: direction,
        createdAt: DateTime.now(),
      ));
    } on PlatformException catch (e) {
      return Err(InferenceFailure(e.message ?? '번역 실패'));
    } catch (e) {
      return Err(InferenceFailure(e.toString()));
    }
  }
}
