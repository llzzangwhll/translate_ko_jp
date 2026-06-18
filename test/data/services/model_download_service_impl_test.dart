import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:translate_ko_jp/data/services/model_download_service.dart';
import 'package:translate_ko_jp/data/services/model_download_service_impl.dart';

/// Builds a streamed response that emits [bytes] in chunks of [chunkSize].
http.StreamedResponse _streamed(
  List<int> bytes, {
  int status = 200,
  int chunkSize = 4,
  Map<String, String> headers = const {},
}) {
  final chunks = <List<int>>[];
  for (var i = 0; i < bytes.length; i += chunkSize) {
    chunks.add(bytes.sublist(i, (i + chunkSize).clamp(0, bytes.length)));
  }
  return http.StreamedResponse(
    Stream.fromIterable(chunks),
    status,
    contentLength: bytes.length,
    headers: headers,
  );
}

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('mdl_dl_test');
  });

  tearDown(() async {
    if (tmpDir.existsSync()) {
      await tmpDir.delete(recursive: true);
    }
  });

  String destPath() => '${tmpDir.path}/model.task';

  test('emits progress and writes file, final event done=true', () async {
    final payload = utf8.encode('hello-gemma-model-bytes');
    final client = MockClient.streaming((request, bodyStream) async {
      expect(request.url.toString(), 'https://example.com/m.task');
      return _streamed(payload, chunkSize: 5);
    });

    final service = ModelDownloadServiceImpl(clientFactory: () => client);

    final events = <DownloadProgress>[];
    await for (final p in service.download(
      url: 'https://example.com/m.task',
      destPath: destPath(),
    )) {
      events.add(p);
    }

    // received is monotonically non-decreasing.
    for (var i = 1; i < events.length; i++) {
      expect(events[i].received, greaterThanOrEqualTo(events[i - 1].received));
    }
    expect(events.last.done, isTrue);
    expect(events.last.received, payload.length);
    expect(events.last.total, payload.length);

    final file = File(destPath());
    expect(file.existsSync(), isTrue);
    expect(await file.readAsBytes(), payload);
    // partial file removed after rename.
    expect(File('${destPath()}.part').existsSync(), isFalse);
  });

  test('checksum mismatch throws and leaves no dest file', () async {
    final payload = utf8.encode('corrupt-bytes');
    final client = MockClient.streaming(
      (request, bodyStream) async => _streamed(payload),
    );
    final service = ModelDownloadServiceImpl(clientFactory: () => client);

    expect(
      () => service
          .download(
            url: 'https://example.com/m.task',
            destPath: destPath(),
            sha256: 'deadbeef', // wrong
          )
          .drain<void>(),
      throwsA(isA<ModelDownloadException>()),
    );

    // give the stream a tick to settle, then assert no dest file.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(File(destPath()).existsSync(), isFalse);
  });

  test('valid checksum passes verification', () async {
    final payload = utf8.encode('good-bytes-1234');
    final expected = sha256.convert(payload).toString();
    final client = MockClient.streaming(
      (request, bodyStream) async => _streamed(payload),
    );
    final service = ModelDownloadServiceImpl(clientFactory: () => client);

    final last = await service
        .download(
          url: 'https://example.com/m.task',
          destPath: destPath(),
          sha256: expected,
        )
        .last;

    expect(last.done, isTrue);
    expect(File(destPath()).readAsBytesSync(), payload);
  });

  test('resumes from existing .part file via Range header', () async {
    final full = utf8.encode('0123456789ABCDEF'); // 16 bytes
    // pre-seed a partial download of the first 6 bytes.
    final part = File('${destPath()}.part');
    await part.writeAsBytes(full.sublist(0, 6));

    String? sentRange;
    final client = MockClient.streaming((request, bodyStream) async {
      sentRange = request.headers['range'] ?? request.headers['Range'];
      // server returns the remaining bytes with 206 Partial Content.
      final remaining = full.sublist(6);
      return http.StreamedResponse(
        Stream.fromIterable([remaining]),
        206,
        contentLength: remaining.length,
        headers: {
          HttpHeaders.contentRangeHeader: 'bytes 6-15/16',
        },
      );
    });
    final service = ModelDownloadServiceImpl(clientFactory: () => client);

    final last = await service
        .download(
          url: 'https://example.com/m.task',
          destPath: destPath(),
        )
        .last;

    expect(sentRange, 'bytes=6-');
    expect(last.done, isTrue);
    expect(last.received, full.length); // total reflects pre-existing bytes
    expect(File(destPath()).readAsBytesSync(), full);
  });

  test('cancel stops the stream with ModelDownloadException', () async {
    final completer = Completer<List<int>>();
    // a stream that never completes until we complete the completer.
    final neverEnding = Stream<List<int>>.fromFuture(completer.future);
    final client = MockClient.streaming(
      (request, bodyStream) async => http.StreamedResponse(
        neverEnding,
        200,
        contentLength: 100,
      ),
    );
    final service = ModelDownloadServiceImpl(clientFactory: () => client);

    final errors = <Object>[];
    final sub = service
        .download(url: 'https://example.com/m.task', destPath: destPath())
        .listen((_) {}, onError: errors.add);

    service.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();
    completer.complete(<int>[]);

    expect(errors, isNotEmpty);
    expect(errors.first, isA<ModelDownloadException>());
  });
}
