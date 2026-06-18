import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/data/services/tts_service_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('constructs without throwing', () {
    expect(TtsServiceImpl.new, returnsNormally);
  });
}
