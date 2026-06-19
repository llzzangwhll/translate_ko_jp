/// Configuration for the model to download: source URL, expected checksum,
/// optional auth headers, and the target filename in the app documents dir.
class ModelConfig {
  final String url;
  final String fileName;

  /// Expected lowercase hex SHA-256 of the downloaded file. Null disables
  /// checksum verification (e.g. for sources that do not publish a hash).
  final String? sha256;

  /// Optional headers (e.g. Gemma license / auth token) injected into the
  /// download request.
  final Map<String, String>? headers;

  const ModelConfig({
    required this.url,
    required this.fileName,
    this.sha256,
    this.headers,
  });

  /// Default model: Gemma 4 E2B (.task), on-device build.
  const ModelConfig.gemmaE2B()
      : url =
            'https://storage.googleapis.com/translate-ko-jp-models/gemma-4-e2b.task',
        fileName = 'gemma-4-e2b.task',
        // TODO(ship): set the real Gemma 4 E2B download URL and SHA-256 before release.
        sha256 = null,
        headers = null;

  /// Named constructor for Hugging Face (or any authenticated) downloads.
  ///
  /// - [token]: when non-null and non-empty, sets `Authorization: Bearer <token>`
  ///   header. Token must come from `--dart-define=HF_TOKEN=...` — never
  ///   hardcode it.
  /// - [fileName]: if omitted, derived from the last path segment of [url].
  ///   Falls back to `'gemma-4-e2b.task'` if the segment is empty.
  /// - [sha256]: optional lowercase hex digest; null disables verification
  ///   (a warning is logged at download time).
  ModelConfig.huggingFace({
    required this.url,
    this.sha256,
    String? token,
    String? fileName,
  })  : headers = (token != null && token.isNotEmpty)
            ? {'Authorization': 'Bearer $token'}
            : null,
        fileName = (fileName != null && fileName.isNotEmpty)
            ? fileName
            : _fileNameFromUrl(url);

  /// Creates a [ModelConfig] from compile-time `--dart-define` values.
  ///
  /// Supported defines:
  /// - `MODEL_URL` — full HTTPS URL of the `.task` file to download.
  ///   Default is a best-guess Hugging Face resolve URL; **verify the exact
  ///   HF repo/file path before release** and override via `--dart-define`.
  /// - `MODEL_SHA256` — optional lowercase hex SHA-256 of the file.
  ///   If omitted, checksum verification is skipped (a warning is logged).
  /// - `HF_TOKEN` — Hugging Face Bearer token. Must NOT be committed;
  ///   supply via `--dart-define=HF_TOKEN=<your_token>` at build/run time.
  factory ModelConfig.fromEnvironment() {
    const url = String.fromEnvironment(
      'MODEL_URL',
      defaultValue:
          'https://huggingface.co/google/gemma-4-e2b-it-litert/resolve/main/gemma-4-e2b-it-int4.task',
    );
    const sha = String.fromEnvironment('MODEL_SHA256');
    const token = String.fromEnvironment('HF_TOKEN');
    return ModelConfig.huggingFace(
      url: url,
      sha256: sha.isEmpty ? null : sha,
      token: token.isEmpty ? null : token,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ModelConfig &&
      other.url == url &&
      other.fileName == fileName &&
      other.sha256 == sha256 &&
      _mapEquals(other.headers, headers);

  @override
  int get hashCode => Object.hash(url, fileName, sha256, _mapHash(headers));

  static String _fileNameFromUrl(String url) {
    final segment = url.split('/').last;
    return segment.isNotEmpty ? segment : 'gemma-4-e2b.task';
  }

  static bool _mapEquals(Map<String, String>? a, Map<String, String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static int _mapHash(Map<String, String>? m) {
    if (m == null) return 0;
    var h = 0;
    for (final entry in m.entries) {
      h ^= Object.hash(entry.key, entry.value);
    }
    return h;
  }
}
