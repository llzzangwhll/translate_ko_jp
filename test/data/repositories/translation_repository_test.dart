import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/data/repositories/translation_repository.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import '../../fakes/fake_inference_service.dart';

void main() {
  test('returns Ok with translated text on success', () async {
    final inference = FakeInferenceService(response: 'こんにちは');
    final repo = TranslationRepositoryImpl(inference);

    final result = await repo.translate(
      text: '안녕하세요',
      direction: LanguageDirection.koToJa(),
    );

    expect(result, isA<Ok<TranslationResult>>());
    final value = (result as Ok<TranslationResult>).value;
    expect(value.sourceText, '안녕하세요');
    expect(value.translatedText, 'こんにちは');
    expect(value.direction, LanguageDirection.koToJa());
    expect(inference.lastDirection, LanguageDirection.koToJa());
  });

  test('maps PlatformException to InferenceFailure', () async {
    final inference = FakeInferenceService(
      throwOnTranslate: PlatformException(code: 'TRANSLATE_FAILED', message: 'boom'),
    );
    final repo = TranslationRepositoryImpl(inference);

    final result = await repo.translate(
      text: '테스트',
      direction: LanguageDirection.koToJa(),
    );

    expect(result, isA<Err<TranslationResult>>());
    expect((result as Err<TranslationResult>).failure, isA<InferenceFailure>());
    expect(result.failure.message, contains('boom'));
  });

  test('returns InferenceFailure when model produces empty output', () async {
    final inference = FakeInferenceService(response: '   ');
    final repo = TranslationRepositoryImpl(inference);

    final result = await repo.translate(
      text: '테스트',
      direction: LanguageDirection.koToJa(),
    );

    expect(result, isA<Err<TranslationResult>>());
    expect((result as Err<TranslationResult>).failure, isA<InferenceFailure>());
  });
}
