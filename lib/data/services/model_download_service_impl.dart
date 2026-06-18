import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'model_download_service.dart';

/// Thrown on any download/verification failure. Repository maps this to a
/// NetworkFailure or ModelFailure.
class ModelDownloadException implements Exception {
  final String message;
  const ModelDownloadException(this.message);
  @override
  String toString() => 'ModelDownloadException: $message';
}

/// HTTP streaming download with byte progress, HTTP Range resume, cancel,
/// and SHA-256 checksum verification. Writes to `<destPath>.part` then
/// renames to [destPath] on success.
class ModelDownloadServiceImpl implements ModelDownloadService {
  /// Injectable for tests (MockClient). Each download uses a fresh client.
  final http.Client Function() _clientFactory;

  // Per-download cancel completer; created fresh each time download() is called.
  Completer<Never>? _cancelCompleter;

  ModelDownloadServiceImpl({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? (() => http.Client());

  @override
  void cancel() {
    final c = _cancelCompleter;
    if (c != null && !c.isCompleted) {
      c.completeError(const ModelDownloadException('cancelled'));
    }
  }

  @override
  Stream<DownloadProgress> download({
    required String url,
    required String destPath,
    String? sha256,
    Map<String, String>? headers,
  }) {
    // Create a fresh cancel completer for this download.
    final cancelCompleter = Completer<Never>();
    _cancelCompleter = cancelCompleter;
    // Attach a no-op error handler so the future is always "handled" even if
    // cancel() is called before _runDownload wires up its own handler.
    // ignore: unawaited_futures
    cancelCompleter.future.then<void>((_) {}, onError: (_) {});

    final controller = StreamController<DownloadProgress>();
    _runDownload(
      url: url,
      destPath: destPath,
      sha256: sha256,
      headers: headers,
      cancelFuture: cancelCompleter.future,
      controller: controller,
    );
    return controller.stream;
  }

  Future<void> _runDownload({
    required String url,
    required String destPath,
    required String? sha256,
    required Map<String, String>? headers,
    required Future<Never> cancelFuture,
    required StreamController<DownloadProgress> controller,
  }) async {
    final partFile = File('$destPath.part');
    final destFile = File(destPath);
    IOSink? sink;
    final client = _clientFactory();

    // Races [future] against [cancelFuture].
    Future<T> raceCancel<T>(Future<T> future) =>
        Future.any<T>([future, cancelFuture]);

    try {
      // Resume support: how many bytes already on disk.
      var existing = 0;
      if (await partFile.exists()) {
        existing = await partFile.length();
      }

      final request = http.Request('GET', Uri.parse(url));
      if (headers != null) request.headers.addAll(headers);
      if (existing > 0) {
        request.headers[HttpHeaders.rangeHeader] = 'bytes=$existing-';
      }

      final response = await raceCancel(client.send(request));

      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw ModelDownloadException('HTTP ${response.statusCode} for $url');
      }

      // If we asked for a range but server ignored it (200), restart clean.
      if (existing > 0 && response.statusCode == HttpStatus.ok) {
        existing = 0;
        await _safeDelete(partFile);
      }

      final contentLength = response.contentLength ?? 0;
      final total = contentLength + existing;

      sink = partFile.openWrite(
        mode: existing > 0 ? FileMode.append : FileMode.write,
      );

      var received = existing;
      controller.add(
          DownloadProgress(received: received, total: total, done: false));

      // Stream chunks, racing cancel on each next-chunk future.
      await for (final chunk
          in _makeRacedStream(response.stream, cancelFuture)) {
        sink.add(chunk);
        received += chunk.length;
        controller.add(
            DownloadProgress(received: received, total: total, done: false));
      }

      await sink.flush();
      await sink.close();
      sink = null;

      // Checksum verification over the full assembled part file.
      if (sha256 != null) {
        final digest = await _sha256OfFile(partFile);
        if (digest != sha256.toLowerCase()) {
          await _safeDelete(partFile);
          throw ModelDownloadException(
              'checksum mismatch: expected $sha256, got $digest');
        }
      }

      // Atomic-ish finalize: rename part -> dest.
      if (await destFile.exists()) await destFile.delete();
      await partFile.rename(destPath);

      controller.add(DownloadProgress(
        received: received,
        total: total > 0 ? total : received,
        done: true,
      ));
      controller.close();
    } on ModelDownloadException catch (e) {
      await _closeSink(sink);
      client.close();
      controller.addError(e);
      controller.close();
    } catch (e) {
      await _closeSink(sink);
      client.close();
      controller.addError(ModelDownloadException(e.toString()));
      controller.close();
    }
    // Normal path closes client here too (double-close is a no-op for most clients).
    client.close();
  }

  /// Returns a stream that forwards chunks from [source] but errors immediately
  /// (with [ModelDownloadException]) if [cancelFuture] completes (with error).
  Stream<List<int>> _makeRacedStream(
    Stream<List<int>> source,
    Future<Never> cancelFuture,
  ) {
    late StreamController<List<int>> ctrl;
    StreamSubscription<List<int>>? dataSub;

    ctrl = StreamController<List<int>>(
      onListen: () {
        dataSub = source.listen(
          (chunk) {
            if (!ctrl.isClosed) ctrl.add(chunk);
          },
          onError: (Object e, StackTrace st) {
            if (!ctrl.isClosed) {
              ctrl.addError(e, st);
              ctrl.close();
            }
          },
          onDone: () {
            if (!ctrl.isClosed) ctrl.close();
          },
        );

        // Wire cancel signal.
        cancelFuture.then(
          (_) {/* never completes normally */},
          onError: (Object e, StackTrace st) {
            dataSub?.cancel();
            if (!ctrl.isClosed) {
              ctrl.addError(e, st);
              ctrl.close();
            }
          },
        );
      },
      onCancel: () => dataSub?.cancel(),
    );

    return ctrl.stream;
  }

  Future<void> _closeSink(IOSink? sink) async {
    if (sink == null) return;
    try {
      await sink.flush();
      await sink.close();
    } catch (_) {}
  }

  Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
