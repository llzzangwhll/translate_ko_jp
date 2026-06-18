class DownloadProgress {
  final int received;
  final int total;
  final bool done;
  const DownloadProgress({
    required this.received,
    required this.total,
    required this.done,
  });
  double get fraction => total > 0 ? received / total : 0.0;
}

abstract interface class ModelDownloadService {
  Stream<DownloadProgress> download({
    required String url,
    required String destPath,
    String? sha256,
    Map<String, String>? headers,
  });
  void cancel();
}
