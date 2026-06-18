import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/core/failure.dart';

void main() {
  test('Ok exposes value and isOk', () {
    const Result<int> r = Ok(42);
    expect(r.isOk, isTrue);
    expect(r.valueOrNull, 42);
    expect(r.failureOrNull, isNull);
  });

  test('Err exposes failure and not ok', () {
    const Result<int> r = Err(NetworkFailure('boom'));
    expect(r.isOk, isFalse);
    expect(r.valueOrNull, isNull);
    expect(r.failureOrNull, isA<NetworkFailure>());
    expect(r.failureOrNull!.message, 'boom');
  });
}
