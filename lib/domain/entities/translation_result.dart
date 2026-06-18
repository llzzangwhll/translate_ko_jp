import 'language_direction.dart';

class TranslationResult {
  final int? id;
  final String sourceText;
  final String translatedText;
  final LanguageDirection direction;
  final DateTime createdAt;

  const TranslationResult({
    this.id,
    required this.sourceText,
    required this.translatedText,
    required this.direction,
    required this.createdAt,
  });

  TranslationResult copyWith({int? id}) => TranslationResult(
        id: id ?? this.id,
        sourceText: sourceText,
        translatedText: translatedText,
        direction: direction,
        createdAt: createdAt,
      );
}
