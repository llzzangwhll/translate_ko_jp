enum Language {
  ko,
  ja;

  String get sttLocale => this == Language.ko ? 'ko_KR' : 'ja_JP';
  String get ttsCode => this == Language.ko ? 'ko-KR' : 'ja-JP';
  String get nativeLabel => this == Language.ko ? '한국어' : '日本語';
  String get promptLabel => this == Language.ko ? 'Korean' : 'Japanese';
  Language get opposite => this == Language.ko ? Language.ja : Language.ko;
}
