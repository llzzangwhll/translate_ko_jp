import '../../core/language.dart';

class LanguageDirection {
  final Language from;
  final Language to;
  const LanguageDirection({required this.from, required this.to});

  factory LanguageDirection.koToJa() =>
      const LanguageDirection(from: Language.ko, to: Language.ja);
  factory LanguageDirection.jaToKo() =>
      const LanguageDirection(from: Language.ja, to: Language.ko);

  LanguageDirection get reversed => LanguageDirection(from: to, to: from);
  bool get isKoToJa => from == Language.ko;

  @override
  bool operator ==(Object other) =>
      other is LanguageDirection && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(from, to);
}
