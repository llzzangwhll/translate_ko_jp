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

  group('ModelConfig.huggingFace', () {
    test('sets Authorization header when token is non-empty', () {
      final config = ModelConfig.huggingFace(
        url: 'https://huggingface.co/foo/bar/resolve/main/model.task',
        token: 'hf_abc',
      );
      expect(config.headers, isNotNull);
      expect(config.headers!['Authorization'], 'Bearer hf_abc');
    });

    test('headers is null when token is null', () {
      final config = ModelConfig.huggingFace(
        url: 'https://huggingface.co/foo/bar/resolve/main/model.task',
        token: null,
      );
      expect(config.headers, isNull);
    });

    test('headers is null when token is empty string', () {
      final config = ModelConfig.huggingFace(
        url: 'https://huggingface.co/foo/bar/resolve/main/model.task',
        token: '',
      );
      expect(config.headers, isNull);
    });

    test('derives fileName from last URL path segment', () {
      final config = ModelConfig.huggingFace(
        url: 'https://huggingface.co/foo/bar/resolve/main/model-x.task',
      );
      expect(config.fileName, 'model-x.task');
    });

    test('uses explicit fileName when provided', () {
      final config = ModelConfig.huggingFace(
        url: 'https://huggingface.co/foo/bar/resolve/main/model-x.task',
        fileName: 'custom-name.task',
      );
      expect(config.fileName, 'custom-name.task');
    });

    test('falls back to gemma-4-e2b.task when URL segment is empty', () {
      // Edge case: url ends in '/' so last segment is empty.
      final config = ModelConfig.huggingFace(url: 'https://example.com/');
      expect(config.fileName, 'gemma-4-e2b.task');
    });

    test('sha256 is passed through', () {
      final config = ModelConfig.huggingFace(
        url: 'https://huggingface.co/foo/bar/resolve/main/model.task',
        sha256: 'deadbeef01',
      );
      expect(config.sha256, 'deadbeef01');
    });
  });

  group('ModelConfig.fromEnvironment', () {
    test('returns non-null config with non-empty url and fileName', () {
      // In unit tests, no --dart-define is set; the factory uses defaults.
      final config = ModelConfig.fromEnvironment();
      expect(config.url, isNotEmpty);
      expect(config.url, startsWith('https://'));
      expect(config.fileName, isNotEmpty);
    });

    test('sha256 is null when MODEL_SHA256 not defined', () {
      final config = ModelConfig.fromEnvironment();
      // No --dart-define=MODEL_SHA256 in test runner → null.
      expect(config.sha256, isNull);
    });

    test('headers is null when HF_TOKEN not defined', () {
      final config = ModelConfig.fromEnvironment();
      // No --dart-define=HF_TOKEN in test runner → null.
      expect(config.headers, isNull);
    });
  });
}
