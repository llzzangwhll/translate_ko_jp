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

  @override
  bool operator ==(Object other) =>
      other is ModelConfig &&
      other.url == url &&
      other.fileName == fileName &&
      other.sha256 == sha256 &&
      _mapEquals(other.headers, headers);

  @override
  int get hashCode => Object.hash(url, fileName, sha256, _mapHash(headers));

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
