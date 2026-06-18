import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/core/language.dart';

void main() {
  test('ko maps to correct codes', () {
    expect(Language.ko.sttLocale, 'ko_KR');
    expect(Language.ko.ttsCode, 'ko-KR');
    expect(Language.ko.nativeLabel, '한국어');
    expect(Language.ko.promptLabel, 'Korean');
    expect(Language.ko.opposite, Language.ja);
  });

  test('ja maps to correct codes', () {
    expect(Language.ja.sttLocale, 'ja_JP');
    expect(Language.ja.ttsCode, 'ja-JP');
    expect(Language.ja.nativeLabel, '日本語');
    expect(Language.ja.promptLabel, 'Japanese');
    expect(Language.ja.opposite, Language.ko);
  });
}
