import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/data/services/speech_service_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('isAvailable is false before initialize', () {
    final service = SpeechServiceImpl();
    expect(service.isAvailable, isFalse);
  });
}
