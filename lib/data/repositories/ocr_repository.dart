import 'package:flutter/services.dart';
import '../../core/failure.dart';
import '../../core/result.dart';
import '../../domain/entities/language_direction.dart';
import '../services/ocr_service.dart';

abstract interface class OcrRepository {
  /// Recognizes text in [imagePath], expecting the source language of
  /// [direction]. Returns an error if nothing readable is found.
  Future<Result<String>> recognizeText({
    required String imagePath,
    required LanguageDirection direction,
  });
}

class OcrRepositoryImpl implements OcrRepository {
  final OcrService _ocr;
  OcrRepositoryImpl(this._ocr);

  @override
  Future<Result<String>> recognizeText({
    required String imagePath,
    required LanguageDirection direction,
  }) async {
    try {
      final raw = await _ocr.recognize(
        imagePath: imagePath,
        language: direction.from,
      );
      final text = raw.trim();
      if (text.isEmpty) {
        return const Err(InferenceFailure('문자를 인식하지 못했습니다'));
      }
      return Ok(text);
    } on PlatformException catch (e) {
      return Err(InferenceFailure(e.message ?? '문자 인식 실패'));
    } catch (e) {
      return Err(InferenceFailure(e.toString()));
    }
  }
}
