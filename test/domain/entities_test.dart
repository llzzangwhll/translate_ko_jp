import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/core/language.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';

void main() {
  test('koToJa factory and reversed', () {
    final d = LanguageDirection.koToJa();
    expect(d.from, Language.ko);
    expect(d.to, Language.ja);
    expect(d.isKoToJa, isTrue);

    final r = d.reversed;
    expect(r.from, Language.ja);
    expect(r.to, Language.ko);
    expect(r.isKoToJa, isFalse);
  });

  test('LanguageDirection equality', () {
    expect(LanguageDirection.koToJa(), LanguageDirection.koToJa());
    expect(LanguageDirection.koToJa() == LanguageDirection.jaToKo(), isFalse);
  });

  test('TranslationResult copyWith sets id', () {
    final t = TranslationResult(
      sourceText: '안녕',
      translatedText: 'こんにちは',
      direction: LanguageDirection.koToJa(),
      createdAt: DateTime(2026, 1, 1),
    );
    expect(t.id, isNull);
    expect(t.copyWith(id: 5).id, 5);
    expect(t.copyWith(id: 5).sourceText, '안녕');
  });
}
