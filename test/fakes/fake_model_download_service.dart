import 'package:translate_ko_jp/data/services/model_download_service.dart';

/// Fake [ModelDownloadService] that replays a scripted progress stream and
/// records the args it was called with.
class FakeModelDownloadService implements ModelDownloadService {
  List<DownloadProgress> script = const [];
  Object? throwError;

  String? lastUrl;
  String? lastDestPath;
  String? lastSha256;
  Map<String, String>? lastHeaders;
  bool cancelCalled = false;

  @override
  Stream<DownloadProgress> download({
    required String url,
    required String destPath,
    String? sha256,
    Map<String, String>? headers,
  }) async* {
    lastUrl = url;
    lastDestPath = destPath;
    lastSha256 = sha256;
    lastHeaders = headers;
    if (throwError != null) {
      throw throwError!;
    }
    for (final p in script) {
      yield p;
    }
  }

  @override
  void cancel() {
    cancelCalled = true;
  }
}
