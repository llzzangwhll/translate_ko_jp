import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/data/services/model_config.dart';

void main() {
  group('ModelConfig', () {
    test('gemmaE2B default exposes url, checksum, filename', () {
      const config = ModelConfig.gemmaE2B();

      expect(config.url, isNotEmpty);
      expect(config.url, startsWith('https://'));
      expect(config.fileName, endsWith('.task'));
      expect(config.sha256, isNull);
      expect(config.headers, isNull);
    });

    test('custom config holds provided values', () {
      const config = ModelConfig(
        url: 'https://example.com/model.task',
        fileName: 'model.task',
        sha256: 'abc123',
        headers: {'Authorization': 'Bearer t'},
      );

      expect(config.url, 'https://example.com/model.task');
      expect(config.fileName, 'model.task');
      expect(config.sha256, 'abc123');
      expect(config.headers, {'Authorization': 'Bearer t'});
    });

    test('value equality holds for identical configs', () {
      const a = ModelConfig.gemmaE2B();
      const b = ModelConfig.gemmaE2B();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
