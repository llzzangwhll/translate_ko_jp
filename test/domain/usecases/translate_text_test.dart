import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/data/repositories/translation_repository.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/usecases/translate_text.dart';
import '../../fakes/fake_inference_service.dart';

void main() {
  test('TranslateText delegates to repository and returns Result', () async {
    final TranslationRepository repo = TranslationRepositoryImpl(FakeInferenceService(response: 'こんにちは'));
    final useCase = TranslateText(repo);

    final result = await useCase(
      text: '안녕하세요',
      direction: LanguageDirection.koToJa(),
    );

    expect(result.isOk, isTrue);
    expect(result.valueOrNull!.translatedText, 'こんにちは');
  });
}
