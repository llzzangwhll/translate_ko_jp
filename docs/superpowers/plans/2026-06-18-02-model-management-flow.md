# 모델 관리 플로우 (Model Management) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 앱이 Gemma 4 E2B `.task` 모델을 인앱으로 다운로드(진행률/재개/취소/SHA-256 검증)하고 추론 엔진에 로드한 뒤 번역 화면으로 진입하는 모델 관리 플로우를 TDD로 구현한다.

**Architecture:** `View(SetupScreen) → ViewModel(SetupController) → UseCase(EnsureModelReady) → Repository(ModelRepository) → Service(ModelDownloadService / InferenceService)` 계층을 따른다. `ModelDownloadService`는 `http` 스트리밍 + `crypto` SHA-256으로 외부 네트워크를 격리하고, `ModelRepository`가 `InferenceService`(foundation/plan 01 소유)를 소비하여 `ModelStatus` 상태 머신을 계산한다. 모든 외부 의존은 인터페이스 뒤에 있어 테스트는 `MockClient`/`FakeInferenceService`로 완전 격리된다.

**Tech Stack:** Flutter, Dart 3, GetX, http, crypto, path_provider, flutter_test

---

## 사전 조건 (Plan 00 Foundation 산출물)

이 플로우는 plan 00이 만든 다음 파일이 **이미 존재**한다고 가정한다. 없으면 plan 00을 먼저 완료할 것.

- `lib/core/result.dart` — `Result<T>` = `Ok<T>` | `Err<T>`
- `lib/core/failure.dart` — `Failure` 계층 (`ModelFailure`, `NetworkFailure` 등)
- `lib/core/language.dart` — `Language` enum
- `lib/domain/entities/language_direction.dart`
- `lib/domain/entities/model_status.dart` — `enum ModelStatus { notDownloaded, downloading, downloaded, loaded, error }`
- `lib/data/services/model_download_service.dart` — `ModelDownloadService` 인터페이스 + `DownloadProgress`
- `lib/data/services/inference_service.dart` — `InferenceService` 인터페이스
- `lib/data/repositories/model_repository.dart` 의 **인터페이스 시그니처**(아래 계약과 동일)
- `lib/app/routes.dart` — `Routes.translation` 라우트 상수 정의

> **계약 정확도:** 아래 모든 시그니처는 `2026-06-18-00-INDEX.md`의 "공유 계약" 섹션과 **정확히** 일치한다. 한 글자도 바꾸지 말 것.

### 이 플로우가 소비하는 계약 (복붙 금지 — 참조만)

```dart
// lib/domain/entities/model_status.dart
enum ModelStatus { notDownloaded, downloading, downloaded, loaded, error }

// lib/data/services/inference_service.dart
abstract interface class InferenceService {
  Future<bool> modelExists();
  Future<bool> isLoaded();
  Future<void> load({String? modelPath});
  Future<String> translate({required String text, required LanguageDirection direction});
  Future<void> dispose();
}

// lib/data/services/model_download_service.dart
class DownloadProgress {
  final int received;
  final int total;
  final bool done;
  const DownloadProgress({required this.received, required this.total, required this.done});
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

// lib/data/repositories/model_repository.dart (인터페이스 — 이 플로우가 impl 작성)
abstract interface class ModelRepository {
  Future<ModelStatus> currentStatus();
  Stream<DownloadProgress> download(); // uses configured URL/checksum
  Future<Result<void>> load();
}
```

---

## 공유 Fake 계약 (테스트 격리)

이 플로우와 plan 01 둘 다 `InferenceService`의 테스트 더블이 필요하다. **머지 충돌을 피하기 위해** 이 플로우는 모델 관리 전용 fake를 **별도 파일명**으로 둔다:

- 파일: `test/fakes/fake_inference_service_model.dart`
- 클래스명: `FakeInferenceServiceModel`

이 fake는 자기완결적(self-contained)이며 plan 01의 `test/fakes/fake_inference_service.dart`(`FakeInferenceService`)와 절대 충돌하지 않는다. plan 05 통합 시 두 fake를 단일 파일로 합칠지 여부는 통합 plan에서 결정한다(이 plan의 범위 밖).

`FakeInferenceServiceModel`의 제어 가능한 동작:
- `existsValue`(bool), `loadedValue`(bool) — `modelExists()`/`isLoaded()` 반환값 제어
- `throwOnLoad`(Object?) — 설정 시 `load()`가 해당 객체를 throw
- `loadCalled`(bool), `lastModelPath`(String?) — 호출 검증용

---

## 작업 경계 (머지 충돌 방지)

- `app/bindings.dart`, `app/routes.dart`를 **수정하지 않는다**. DI는 `lib/app/model_deps.dart`의 `registerModelDeps()`로만 노출하고 plan 05가 `AppBinding`에서 호출한다.
- 네이티브 코드 작성 금지 (`MediaPipeInferenceService`는 plan 01/04 소유).
- 번역 라우트 진입은 foundation의 `Routes.translation`을 **참조**만 한다(재정의 금지).
- 기존 `lib/controllers/model_setup_controller.dart`, `lib/views/model_setup_screen.dart`, `lib/services/gemma_service.dart`는 **건드리지 않는다**(제거는 plan 05).

---

## Task 0: 의존성 추가 (`crypto`)

**Files:**
- Modify: `pubspec.yaml`

- [ ] **0.1 — `crypto` 추가:** `pubspec.yaml`의 `dependencies:` 블록에서 `http: ^1.2.0` 아래 줄에 다음을 추가한다.

  ```yaml
    http: ^1.2.0
    crypto: ^3.0.3
  ```

- [ ] **0.2 — 패키지 받기 (run-to-pass):**

  ```bash
  flutter pub get
  ```

  기대: `Got dependencies!` 출력, `crypto`가 `.dart_tool/package_config.json`에 등장. (참고: `http`, `path_provider`는 이미 존재하므로 추가 변경 없음.)

- [ ] **0.3 — commit:**

  ```bash
  git add pubspec.yaml pubspec.lock
  git commit -m "build: add crypto dependency for model checksum verification"
  ```

---

## Task 1: `ModelConfig` — 모델 다운로드 설정 객체

**Files:**
- Create: `lib/data/services/model_config.dart`
- Test: `test/data/services/model_config_test.dart`

- [ ] **1.1 — 실패 테스트 작성:** `test/data/services/model_config_test.dart`

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:translate_ko_jp/data/services/model_config.dart';

  void main() {
    group('ModelConfig', () {
      test('gemmaE2B default exposes url, checksum, filename', () {
        const config = ModelConfig.gemmaE2B();

        expect(config.url, isNotEmpty);
        expect(config.url, startsWith('https://'));
        expect(config.fileName, endsWith('.task'));
        expect(config.sha256, isNotNull);
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
  ```

- [ ] **1.2 — run-to-fail:**

  ```bash
  flutter test test/data/services/model_config_test.dart
  ```

  기대: 컴파일 실패 — `Error: Couldn't resolve the package 'translate_ko_jp/data/services/model_config.dart'` (파일 없음).

- [ ] **1.3 — 최소 구현:** `lib/data/services/model_config.dart`

  ```dart
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
    ///
    /// NOTE: replace [url]/[sha256] with the canonical hosted artifact before
    /// shipping. The URL must point directly at the `.task` artifact (no HTML
    /// redirect). If the source requires a license token, pass [headers] via a
    /// custom [ModelConfig] instead.
    const ModelConfig.gemmaE2B()
        : url =
              'https://storage.googleapis.com/translate-ko-jp-models/gemma-4-e2b.task',
          fileName = 'gemma-4-e2b.task',
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
  ```

  > 설계 노트: `gemmaE2B()`의 `sha256`은 기본 `null`(미검증)로 둔다. 실제 호스팅 아티팩트의 해시가 확정되면 채운다. 체크섬 로직 자체는 Task 2에서 명시적 해시가 주어졌을 때 동작하도록 테스트한다.

- [ ] **1.4 — run-to-pass:**

  ```bash
  flutter test test/data/services/model_config_test.dart
  ```

  기대: `All tests passed!` (3 tests).

- [ ] **1.5 — commit:**

  ```bash
  git add lib/data/services/model_config.dart test/data/services/model_config_test.dart
  git commit -m "feat: add ModelConfig for model download settings"
  ```

---

## Task 2: `ModelDownloadServiceImpl` — HTTP 스트리밍 다운로드 + 진행률 + 재개 + 체크섬

이 태스크가 이 플로우의 핵심이다. `package:http`의 `MockClient`(`package:http/testing.dart`)로 네트워크를 모의하여 **진행률 방출 / 체크섬 불일치 throw / Range 재개**를 검증한다.

**Files:**
- Create: `lib/data/services/model_download_service_impl.dart`
- Test: `test/data/services/model_download_service_impl_test.dart`

- [ ] **2.1 — 실패 테스트 작성:** `test/data/services/model_download_service_impl_test.dart`

  ```dart
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
  ```

- [ ] **2.2 — run-to-fail:**

  ```bash
  flutter test test/data/services/model_download_service_impl_test.dart
  ```

  기대: 컴파일 실패 — `model_download_service_impl.dart` 및 `ModelDownloadException`/`ModelDownloadServiceImpl` 미정의.

- [ ] **2.3 — 최소 구현:** `lib/data/services/model_download_service_impl.dart`

  ```dart
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

    bool _cancelled = false;

    ModelDownloadServiceImpl({http.Client Function()? clientFactory})
        : _clientFactory = clientFactory ?? (() => http.Client());

    @override
    void cancel() {
      _cancelled = true;
    }

    @override
    Stream<DownloadProgress> download({
      required String url,
      required String destPath,
      String? sha256,
      Map<String, String>? headers,
    }) async* {
      _cancelled = false;

      final partFile = File('$destPath.part');
      final destFile = File(destPath);

      // resume support: how many bytes already on disk.
      var existing = 0;
      if (await partFile.exists()) {
        existing = await partFile.length();
      }

      final client = _clientFactory();
      IOSink? sink;
      try {
        final request = http.Request('GET', Uri.parse(url));
        if (headers != null) {
          request.headers.addAll(headers);
        }
        if (existing > 0) {
          request.headers[HttpHeaders.rangeHeader] = 'bytes=$existing-';
        }

        final response = await client.send(request);

        if (response.statusCode != HttpStatus.ok &&
            response.statusCode != HttpStatus.partialContent) {
          throw ModelDownloadException(
            'HTTP ${response.statusCode} for $url',
          );
        }

        // If we asked for a range but server ignored it (200), restart clean.
        if (existing > 0 && response.statusCode == HttpStatus.ok) {
          existing = 0;
          if (await partFile.exists()) {
            await partFile.delete();
          }
        }

        final contentLength = response.contentLength ?? 0;
        final total = contentLength + existing;

        sink = partFile.openWrite(
          mode: existing > 0 ? FileMode.append : FileMode.write,
        );

        var received = existing;
        // emit an initial event so listeners see resumed baseline.
        yield DownloadProgress(received: received, total: total, done: false);

        await for (final chunk in response.stream) {
          if (_cancelled) {
            throw const ModelDownloadException('cancelled');
          }
          sink.add(chunk);
          received += chunk.length;
          yield DownloadProgress(received: received, total: total, done: false);
        }

        await sink.flush();
        await sink.close();
        sink = null;

        // checksum verification over the full assembled part file.
        if (sha256 != null) {
          final digest = await _sha256OfFile(partFile);
          if (digest != sha256.toLowerCase()) {
            await _safeDelete(partFile);
            throw ModelDownloadException(
              'checksum mismatch: expected $sha256, got $digest',
            );
          }
        }

        // atomic-ish finalize: rename part -> dest.
        if (await destFile.exists()) {
          await destFile.delete();
        }
        await partFile.rename(destPath);

        yield DownloadProgress(
          received: received,
          total: total > 0 ? total : received,
          done: true,
        );
      } on ModelDownloadException {
        rethrow;
      } catch (e) {
        throw ModelDownloadException(e.toString());
      } finally {
        // best-effort close; ignore if already closed.
        try {
          await sink?.flush();
          await sink?.close();
        } catch (_) {}
        client.close();
      }
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
  ```

  > 주의: `crypto`의 `sha256`(Hash)와 인자 `sha256`(String)이 이름 충돌하므로, `model_download_service_impl.dart` 내부에서는 `crypto`의 `sha256`을 그대로 쓰되 파라미터 비교는 `_sha256OfFile` 헬퍼로 캡슐화했다. (테스트 파일에서는 `package:crypto`의 `sha256`을 직접 import해 기대 해시를 계산한다 — 충돌 없음.)

- [ ] **2.4 — run-to-pass:**

  ```bash
  flutter test test/data/services/model_download_service_impl_test.dart
  ```

  기대: `All tests passed!` (5 tests: 진행률, 체크섬 불일치 throw, 정상 체크섬, Range 재개, 취소).

- [ ] **2.5 — commit:**

  ```bash
  git add lib/data/services/model_download_service_impl.dart test/data/services/model_download_service_impl_test.dart
  git commit -m "feat: implement ModelDownloadServiceImpl with progress, resume, checksum"
  ```

---

## Task 3: `FakeInferenceServiceModel` — 테스트용 추론 서비스 더블

**Files:**
- Create: `test/fakes/fake_inference_service_model.dart`

> 이 fake는 다음 태스크(Repository/UseCase/Controller)에서 import하므로 먼저 만든다. 별도 테스트 없음 — 후속 테스트가 이 fake를 검증한다.

- [ ] **3.1 — fake 작성:** `test/fakes/fake_inference_service_model.dart`

  ```dart
  import 'package:translate_ko_jp/data/services/inference_service.dart';
  import 'package:translate_ko_jp/domain/entities/language_direction.dart';

  /// Self-contained fake of [InferenceService] for the model-management flow.
  ///
  /// Named with a `Model` suffix so it never collides with plan 01's
  /// `FakeInferenceService` in `test/fakes/fake_inference_service.dart`.
  class FakeInferenceServiceModel implements InferenceService {
    bool existsValue = false;
    bool loadedValue = false;

    /// If non-null, [load] throws this object.
    Object? throwOnLoad;

    bool loadCalled = false;
    String? lastModelPath;

    @override
    Future<bool> modelExists() async => existsValue;

    @override
    Future<bool> isLoaded() async => loadedValue;

    @override
    Future<void> load({String? modelPath}) async {
      loadCalled = true;
      lastModelPath = modelPath;
      if (throwOnLoad != null) {
        throw throwOnLoad!;
      }
      loadedValue = true;
    }

    @override
    Future<String> translate({
      required String text,
      required LanguageDirection direction,
    }) async =>
        text;

    @override
    Future<void> dispose() async {}
  }
  ```

- [ ] **3.2 — 컴파일 확인 (run):**

  ```bash
  flutter analyze test/fakes/fake_inference_service_model.dart
  ```

  기대: `No issues found!`

- [ ] **3.3 — commit:**

  ```bash
  git add test/fakes/fake_inference_service_model.dart
  git commit -m "test: add FakeInferenceServiceModel for model-management flow"
  ```

---

## Task 4: `ModelRepositoryImpl` — 상태 머신 + 다운로드 위임 + 로드

**Files:**
- Create: `lib/data/repositories/model_repository.dart`
- Test: `test/data/repositories/model_repository_test.dart`
- Test (fake): `test/fakes/fake_model_download_service.dart`

> **계약 주의:** plan 00이 이미 `model_repository.dart`에 `ModelRepository` **인터페이스**를 정의했을 수 있다. 그 경우 이 파일에 인터페이스를 재정의하지 말고 **impl 클래스만 추가**한다. 인터페이스가 없으면 아래처럼 인터페이스 + impl을 함께 작성한다(시그니처는 계약과 정확히 일치).

- [ ] **4.1 — 다운로드 서비스 fake 작성:** `test/fakes/fake_model_download_service.dart`

  ```dart
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
  ```

- [ ] **4.2 — 실패 테스트 작성:** `test/data/repositories/model_repository_test.dart`

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:translate_ko_jp/core/failure.dart';
  import 'package:translate_ko_jp/core/result.dart';
  import 'package:translate_ko_jp/data/repositories/model_repository.dart';
  import 'package:translate_ko_jp/data/services/model_config.dart';
  import 'package:translate_ko_jp/data/services/model_download_service.dart';
  import 'package:translate_ko_jp/domain/entities/model_status.dart';

  import '../../fakes/fake_inference_service_model.dart';
  import '../../fakes/fake_model_download_service.dart';

  void main() {
    late FakeInferenceServiceModel inference;
    late FakeModelDownloadService downloader;
    late ModelRepositoryImpl repo;

    setUp(() {
      inference = FakeInferenceServiceModel();
      downloader = FakeModelDownloadService();
      repo = ModelRepositoryImpl(
        inference: inference,
        downloadService: downloader,
        config: const ModelConfig(
          url: 'https://example.com/m.task',
          fileName: 'm.task',
          sha256: 'abc',
        ),
        resolveDestPath: (fileName) async => '/tmp/$fileName',
      );
    });

    group('currentStatus', () {
      test('loaded when isLoaded true', () async {
        inference.existsValue = true;
        inference.loadedValue = true;
        expect(await repo.currentStatus(), ModelStatus.loaded);
      });

      test('downloaded when exists but not loaded', () async {
        inference.existsValue = true;
        inference.loadedValue = false;
        expect(await repo.currentStatus(), ModelStatus.downloaded);
      });

      test('notDownloaded when model does not exist', () async {
        inference.existsValue = false;
        inference.loadedValue = false;
        expect(await repo.currentStatus(), ModelStatus.notDownloaded);
      });
    });

    group('download', () {
      test('delegates with configured url, destPath and checksum', () async {
        downloader.script = const [
          DownloadProgress(received: 5, total: 10, done: false),
          DownloadProgress(received: 10, total: 10, done: true),
        ];

        final events = await repo.download().toList();

        expect(downloader.lastUrl, 'https://example.com/m.task');
        expect(downloader.lastDestPath, '/tmp/m.task');
        expect(downloader.lastSha256, 'abc');
        expect(events.last.done, isTrue);
      });

      test('passes config headers through', () async {
        repo = ModelRepositoryImpl(
          inference: inference,
          downloadService: downloader,
          config: const ModelConfig(
            url: 'https://example.com/m.task',
            fileName: 'm.task',
            headers: {'Authorization': 'Bearer x'},
          ),
          resolveDestPath: (fileName) async => '/tmp/$fileName',
        );
        downloader.script = const [
          DownloadProgress(received: 1, total: 1, done: true),
        ];

        await repo.download().toList();

        expect(downloader.lastHeaders, {'Authorization': 'Bearer x'});
      });
    });

    group('load', () {
      test('returns Ok when load succeeds', () async {
        final result = await repo.load();
        expect(result, isA<Ok<void>>());
        expect(inference.loadCalled, isTrue);
      });

      test('passes resolved model path to inference.load', () async {
        await repo.load();
        expect(inference.lastModelPath, '/tmp/m.task');
      });

      test('returns Err(ModelFailure) when load throws', () async {
        inference.throwOnLoad = Exception('bad model');
        final result = await repo.load();
        expect(result, isA<Err<void>>());
        final failure = (result as Err<void>).failure;
        expect(failure, isA<ModelFailure>());
        expect(failure.message, contains('bad model'));
      });
    });

    test('cancelDownload delegates to service', () {
      repo.cancelDownload();
      expect(downloader.cancelCalled, isTrue);
    });
  }
  ```

- [ ] **4.3 — run-to-fail:**

  ```bash
  flutter test test/data/repositories/model_repository_test.dart
  ```

  기대: 컴파일 실패 — `ModelRepositoryImpl` 미정의.

- [ ] **4.4 — 최소 구현:** `lib/data/repositories/model_repository.dart`

  ```dart
  import 'dart:async';

  import 'package:path_provider/path_provider.dart';

  import '../../core/failure.dart';
  import '../../core/result.dart';
  import '../../domain/entities/model_status.dart';
  import '../services/inference_service.dart';
  import '../services/model_config.dart';
  import '../services/model_download_service.dart';

  /// Contract (matches shared contracts in INDEX). If plan 00 already declares
  /// this interface in this file, keep ONE copy and delete the duplicate.
  abstract interface class ModelRepository {
    Future<ModelStatus> currentStatus();
    Stream<DownloadProgress> download(); // uses configured URL/checksum
    Future<Result<void>> load();
  }

  /// Resolves the on-disk destination path for [fileName]. Injectable so tests
  /// avoid path_provider's platform channel.
  typedef ResolveDestPath = Future<String> Function(String fileName);

  Future<String> _defaultResolveDestPath(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$fileName';
  }

  class ModelRepositoryImpl implements ModelRepository {
    final InferenceService _inference;
    final ModelDownloadService _downloadService;
    final ModelConfig _config;
    final ResolveDestPath _resolveDestPath;

    ModelRepositoryImpl({
      required InferenceService inference,
      required ModelDownloadService downloadService,
      required ModelConfig config,
      ResolveDestPath resolveDestPath = _defaultResolveDestPath,
    })  : _inference = inference,
          _downloadService = downloadService,
          _config = config,
          _resolveDestPath = resolveDestPath;

    @override
    Future<ModelStatus> currentStatus() async {
      if (await _inference.isLoaded()) return ModelStatus.loaded;
      if (await _inference.modelExists()) return ModelStatus.downloaded;
      return ModelStatus.notDownloaded;
    }

    @override
    Stream<DownloadProgress> download() async* {
      final destPath = await _resolveDestPath(_config.fileName);
      yield* _downloadService.download(
        url: _config.url,
        destPath: destPath,
        sha256: _config.sha256,
        headers: _config.headers,
      );
    }

    /// Forwards cancellation to the underlying download service.
    void cancelDownload() => _downloadService.cancel();

    @override
    Future<Result<void>> load() async {
      try {
        final destPath = await _resolveDestPath(_config.fileName);
        await _inference.load(modelPath: destPath);
        return const Ok(null);
      } catch (e) {
        return Err(ModelFailure('모델 로드 실패: $e'));
      }
    }
  }
  ```

- [ ] **4.5 — run-to-pass:**

  ```bash
  flutter test test/data/repositories/model_repository_test.dart
  ```

  기대: `All tests passed!` (status 3 + download 2 + load 3 + cancel 1 = 9 tests).

- [ ] **4.6 — commit:**

  ```bash
  git add lib/data/repositories/model_repository.dart test/data/repositories/model_repository_test.dart test/fakes/fake_model_download_service.dart
  git commit -m "feat: implement ModelRepositoryImpl with status, download, load"
  ```

---

## Task 5: `EnsureModelReady` UseCase

**Files:**
- Create: `lib/domain/usecases/ensure_model_ready.dart`
- Test: `test/domain/usecases/ensure_model_ready_test.dart`
- Test (fake): `test/fakes/fake_model_repository.dart`

- [ ] **5.1 — repository fake 작성:** `test/fakes/fake_model_repository.dart`

  ```dart
  import 'package:translate_ko_jp/core/result.dart';
  import 'package:translate_ko_jp/data/repositories/model_repository.dart';
  import 'package:translate_ko_jp/data/services/model_download_service.dart';
  import 'package:translate_ko_jp/domain/entities/model_status.dart';

  class FakeModelRepository implements ModelRepository {
    ModelStatus statusValue = ModelStatus.notDownloaded;
    List<DownloadProgress> downloadScript = const [];
    Result<void> loadResult = const Ok(null);

    bool loadCalled = false;
    int statusCalls = 0;

    @override
    Future<ModelStatus> currentStatus() async {
      statusCalls++;
      return statusValue;
    }

    @override
    Stream<DownloadProgress> download() async* {
      for (final p in downloadScript) {
        yield p;
      }
    }

    @override
    Future<Result<void>> load() async {
      loadCalled = true;
      return loadResult;
    }
  }
  ```

- [ ] **5.2 — 실패 테스트 작성:** `test/domain/usecases/ensure_model_ready_test.dart`

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:translate_ko_jp/core/failure.dart';
  import 'package:translate_ko_jp/core/result.dart';
  import 'package:translate_ko_jp/domain/entities/model_status.dart';
  import 'package:translate_ko_jp/domain/usecases/ensure_model_ready.dart';

  import '../../fakes/fake_model_repository.dart';

  void main() {
    late FakeModelRepository repo;
    late EnsureModelReady useCase;

    setUp(() {
      repo = FakeModelRepository();
      useCase = EnsureModelReady(repo);
    });

    test('notDownloaded -> needsDownload, does not load', () async {
      repo.statusValue = ModelStatus.notDownloaded;

      final outcome = await useCase();

      expect(outcome, isA<Ok<ModelReadiness>>());
      expect((outcome as Ok<ModelReadiness>).value, ModelReadiness.needsDownload);
      expect(repo.loadCalled, isFalse);
    });

    test('already loaded -> ready, does not call load again', () async {
      repo.statusValue = ModelStatus.loaded;

      final outcome = await useCase();

      expect((outcome as Ok<ModelReadiness>).value, ModelReadiness.ready);
      expect(repo.loadCalled, isFalse);
    });

    test('downloaded but not loaded -> loads then ready', () async {
      repo.statusValue = ModelStatus.downloaded;
      repo.loadResult = const Ok(null);

      final outcome = await useCase();

      expect(repo.loadCalled, isTrue);
      expect((outcome as Ok<ModelReadiness>).value, ModelReadiness.ready);
    });

    test('downloaded but load fails -> propagates Err(ModelFailure)', () async {
      repo.statusValue = ModelStatus.downloaded;
      repo.loadResult = const Err(ModelFailure('boom'));

      final outcome = await useCase();

      expect(outcome, isA<Err<ModelReadiness>>());
      expect((outcome as Err<ModelReadiness>).failure, isA<ModelFailure>());
    });
  }
  ```

- [ ] **5.3 — run-to-fail:**

  ```bash
  flutter test test/domain/usecases/ensure_model_ready_test.dart
  ```

  기대: 컴파일 실패 — `EnsureModelReady`, `ModelReadiness` 미정의.

- [ ] **5.4 — 최소 구현:** `lib/domain/usecases/ensure_model_ready.dart`

  ```dart
  import '../../core/result.dart';
  import '../../data/repositories/model_repository.dart';
  import '../entities/model_status.dart';

  /// Outcome of an [EnsureModelReady] check.
  enum ModelReadiness {
    /// Model file is absent; the setup screen must trigger a download.
    needsDownload,

    /// Model is downloaded and loaded into the inference engine.
    ready,
  }

  /// Checks model status and, if the file already exists, loads it.
  /// Returns whether a download is still required, or that the model is ready.
  class EnsureModelReady {
    final ModelRepository _repo;
    const EnsureModelReady(this._repo);

    Future<Result<ModelReadiness>> call() async {
      final status = await _repo.currentStatus();
      switch (status) {
        case ModelStatus.loaded:
          return const Ok(ModelReadiness.ready);
        case ModelStatus.notDownloaded:
        case ModelStatus.error:
          return const Ok(ModelReadiness.needsDownload);
        case ModelStatus.downloading:
        case ModelStatus.downloaded:
          final loadResult = await _repo.load();
          return switch (loadResult) {
            Ok() => const Ok(ModelReadiness.ready),
            Err(failure: final f) => Err(f),
          };
      }
    }
  }
  ```

  > Dart 3 sealed `switch`로 `Result`를 분기한다. `ModelStatus.downloading`도 파일이 존재할 가능성이 있으므로 load를 시도(실패 시 Err 전파)한다.

- [ ] **5.5 — run-to-pass:**

  ```bash
  flutter test test/domain/usecases/ensure_model_ready_test.dart
  ```

  기대: `All tests passed!` (4 tests).

- [ ] **5.6 — commit:**

  ```bash
  git add lib/domain/usecases/ensure_model_ready.dart test/domain/usecases/ensure_model_ready_test.dart test/fakes/fake_model_repository.dart
  git commit -m "feat: add EnsureModelReady use case"
  ```

---

## Task 6: `SetupController` — 반응형 상태 + 다운로드/로드 조율 + 네비게이션

**Files:**
- Create: `lib/presentation/setup/setup_controller.dart`
- Test: `test/presentation/setup/setup_controller_test.dart`

> 네비게이션 부수효과는 주입 가능한 콜백(`onReady`)으로 격리해 위젯 트리 없이 단위 테스트한다. 실제 화면(Task 7)이 `Get.offAllNamed(Routes.translation)`를 이 콜백으로 전달한다.

- [ ] **6.1 — 실패 테스트 작성:** `test/presentation/setup/setup_controller_test.dart`

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:translate_ko_jp/core/result.dart';
  import 'package:translate_ko_jp/data/services/model_download_service.dart';
  import 'package:translate_ko_jp/domain/entities/model_status.dart';
  import 'package:translate_ko_jp/domain/usecases/ensure_model_ready.dart';
  import 'package:translate_ko_jp/presentation/setup/setup_controller.dart';

  import '../../fakes/fake_model_repository.dart';

  void main() {
    late FakeModelRepository repo;
    late EnsureModelReady ensure;
    late SetupController controller;
    var navigatedToTranslation = 0;

    SetupController build() => SetupController(
          repository: repo,
          ensureModelReady: ensure,
          onReady: () => navigatedToTranslation++,
        );

    setUp(() {
      navigatedToTranslation = 0;
      repo = FakeModelRepository();
      ensure = EnsureModelReady(repo);
    });

    test('initial status is notDownloaded', () {
      controller = build();
      expect(controller.status.value, ModelStatus.notDownloaded);
      expect(controller.progress.value, 0.0);
      expect(controller.isBusy.value, isFalse);
    });

    test('checkStatus(loaded) navigates to translation immediately', () async {
      repo.statusValue = ModelStatus.loaded;
      controller = build();

      await controller.checkStatus();

      expect(controller.status.value, ModelStatus.loaded);
      expect(navigatedToTranslation, 1);
    });

    test('checkStatus(notDownloaded) stays on setup, no nav', () async {
      repo.statusValue = ModelStatus.notDownloaded;
      controller = build();

      await controller.checkStatus();

      expect(controller.status.value, ModelStatus.notDownloaded);
      expect(navigatedToTranslation, 0);
    });

    test('startDownload streams progress then loads and navigates', () async {
      repo.statusValue = ModelStatus.notDownloaded;
      repo.downloadScript = const [
        DownloadProgress(received: 50, total: 100, done: false),
        DownloadProgress(received: 100, total: 100, done: true),
      ];
      repo.loadResult = const Ok(null);
      controller = build();

      await controller.startDownload();

      // progress reflects last received fraction (1.0) on completion.
      expect(controller.receivedBytes.value, 100);
      expect(controller.totalBytes.value, 100);
      expect(controller.status.value, ModelStatus.loaded);
      expect(repo.loadCalled, isTrue);
      expect(navigatedToTranslation, 1);
      expect(controller.isBusy.value, isFalse);
    });

    test('startDownload sets error status when load fails', () async {
      repo.statusValue = ModelStatus.notDownloaded;
      repo.downloadScript = const [
        DownloadProgress(received: 100, total: 100, done: true),
      ];
      repo.loadResult = const Err(ModelFailureForTest());
      controller = build();

      await controller.startDownload();

      expect(controller.status.value, ModelStatus.error);
      expect(controller.errorMessage.value, isNotEmpty);
      expect(navigatedToTranslation, 0);
      expect(controller.isBusy.value, isFalse);
    });

    test('cancel resets busy and status to notDownloaded', () async {
      controller = build();
      controller.isBusy.value = true;
      controller.status.value = ModelStatus.downloading;

      controller.cancel();

      expect(controller.isBusy.value, isFalse);
      expect(controller.status.value, ModelStatus.notDownloaded);
    });
  }

  // local Failure subtype for the load-failure test.
  class ModelFailureForTest extends ModelFailure {
    const ModelFailureForTest() : super('load failed in test');
  }
  ```

  > 위 테스트는 `ModelFailure`를 import해야 한다. 파일 상단 import에 `import 'package:translate_ko_jp/core/failure.dart';`를 추가한다(아래 구현 단계에서 컨트롤러가 `ModelFailure`를 노출하지 않으므로 테스트에서만 사용).

- [ ] **6.2 — run-to-fail:**

  ```bash
  flutter test test/presentation/setup/setup_controller_test.dart
  ```

  기대: 컴파일 실패 — `SetupController` 미정의. (`failure.dart` import 누락 시 추가.)

- [ ] **6.3 — 최소 구현:** `lib/presentation/setup/setup_controller.dart`

  ```dart
  import 'package:get/get.dart';

  import '../../core/result.dart';
  import '../../data/repositories/model_repository.dart';
  import '../../data/services/model_download_service.dart';
  import '../../domain/entities/model_status.dart';
  import '../../domain/usecases/ensure_model_ready.dart';

  /// ViewModel for the model setup screen. Observes [ModelStatus], drives the
  /// download (progress / cancel), then loads and navigates to translation.
  class SetupController extends GetxController {
    final ModelRepository _repository;
    final EnsureModelReady _ensureModelReady;

    /// Side-effect-free navigation hook; the screen wires this to
    /// `Get.offAllNamed(Routes.translation)`.
    final void Function() _onReady;

    SetupController({
      required ModelRepository repository,
      required EnsureModelReady ensureModelReady,
      required void Function() onReady,
    })  : _repository = repository,
          _ensureModelReady = ensureModelReady,
          _onReady = onReady;

    final status = ModelStatus.notDownloaded.obs;
    final isBusy = false.obs;
    final receivedBytes = 0.obs;
    final totalBytes = 0.obs;
    final errorMessage = ''.obs;

    /// 0.0..1.0 download fraction for the progress bar.
    double get fraction =>
        totalBytes.value > 0 ? receivedBytes.value / totalBytes.value : 0.0;

    @override
    void onInit() {
      super.onInit();
      checkStatus();
    }

    /// Runs EnsureModelReady. If ready, navigates. Otherwise leaves the screen
    /// in a state where the user can trigger a download.
    Future<void> checkStatus() async {
      errorMessage.value = '';
      final outcome = await _ensureModelReady();
      switch (outcome) {
        case Ok(value: final readiness):
          switch (readiness) {
            case ModelReadiness.ready:
              status.value = ModelStatus.loaded;
              _onReady();
            case ModelReadiness.needsDownload:
              status.value = await _repository.currentStatus();
          }
        case Err(failure: final f):
          status.value = ModelStatus.error;
          errorMessage.value = f.message;
      }
    }

    /// Downloads the configured model, verifies/loads it, then navigates.
    Future<void> startDownload() async {
      isBusy.value = true;
      errorMessage.value = '';
      status.value = ModelStatus.downloading;
      receivedBytes.value = 0;
      totalBytes.value = 0;

      try {
        await for (final p in _repository.download()) {
          receivedBytes.value = p.received;
          totalBytes.value = p.total;
        }
      } catch (e) {
        status.value = ModelStatus.error;
        errorMessage.value = '다운로드 실패: $e';
        isBusy.value = false;
        return;
      }

      status.value = ModelStatus.downloaded;
      await _loadAndNavigate();
      isBusy.value = false;
    }

    Future<void> _loadAndNavigate() async {
      final result = await _repository.load();
      switch (result) {
        case Ok():
          status.value = ModelStatus.loaded;
          _onReady();
        case Err(failure: final f):
          status.value = ModelStatus.error;
          errorMessage.value = f.message;
      }
    }

    /// Retries from the current point: re-checks status (resumes via .part).
    Future<void> retry() async {
      await startDownload();
    }

    /// Cancels an in-flight download and returns to the idle setup state.
    void cancel() {
      if (_repository is ModelRepositoryImpl) {
        (_repository as ModelRepositoryImpl).cancelDownload();
      }
      isBusy.value = false;
      status.value = ModelStatus.notDownloaded;
    }
  }
  ```

  > 설계 노트: `cancel()`은 in-flight `download()` 스트림에 취소를 전파한다. `ModelRepository` 인터페이스에는 `cancel`이 없으므로(계약 고정), impl 타입일 때만 `cancelDownload()`를 호출한다. 재개는 `ModelDownloadServiceImpl`이 `.part` 파일을 보고 Range 헤더로 자동 처리하므로, `retry()`는 `startDownload()`를 다시 호출하기만 하면 된다.

- [ ] **6.4 — run-to-pass:**

  ```bash
  flutter test test/presentation/setup/setup_controller_test.dart
  ```

  기대: `All tests passed!` (6 tests).

- [ ] **6.5 — commit:**

  ```bash
  git add lib/presentation/setup/setup_controller.dart test/presentation/setup/setup_controller_test.dart
  git commit -m "feat: add SetupController orchestrating download, load, navigation"
  ```

---

## Task 7: `SetupScreen` — 진행률/취소/재시도 UI

**Files:**
- Create: `lib/presentation/setup/setup_screen.dart`
- Test: `test/presentation/setup/setup_screen_test.dart`

> 기존 `model_setup_screen.dart`의 정신(단계 카드, 안내 문구, 진행률 바)을 유지하되 수동 파일 선택 대신 **인앱 다운로드** 중심으로 단순화한다. 위젯 테스트는 `Get.put`으로 fake 기반 컨트롤러를 주입하고 렌더링 + 버튼 상호작용을 검증한다.

- [ ] **7.1 — 실패 테스트 작성:** `test/presentation/setup/setup_screen_test.dart`

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:get/get.dart';
  import 'package:translate_ko_jp/domain/entities/model_status.dart';
  import 'package:translate_ko_jp/domain/usecases/ensure_model_ready.dart';
  import 'package:translate_ko_jp/presentation/setup/setup_controller.dart';
  import 'package:translate_ko_jp/presentation/setup/setup_screen.dart';

  import '../../fakes/fake_model_repository.dart';

  void main() {
    setUp(() => Get.reset());
    tearDown(() => Get.reset());

    SetupController register(FakeModelRepository repo) {
      final controller = SetupController(
        repository: repo,
        ensureModelReady: EnsureModelReady(repo),
        onReady: () {},
      );
      Get.put<SetupController>(controller);
      return controller;
    }

    testWidgets('renders title and download button when notDownloaded',
        (tester) async {
      final repo = FakeModelRepository()..statusValue = ModelStatus.notDownloaded;
      final controller = register(repo);
      controller.status.value = ModelStatus.notDownloaded;

      await tester.pumpWidget(const GetMaterialApp(home: SetupScreen()));
      await tester.pump();

      expect(find.text('번역 모델 설정'), findsOneWidget);
      expect(find.byKey(const Key('setup-download-button')), findsOneWidget);
    });

    testWidgets('shows progress bar and MB text while downloading',
        (tester) async {
      final repo = FakeModelRepository();
      final controller = register(repo);
      controller.status.value = ModelStatus.downloading;
      controller.isBusy.value = true;
      controller.receivedBytes.value = 50 * 1024 * 1024;
      controller.totalBytes.value = 100 * 1024 * 1024;

      await tester.pumpWidget(const GetMaterialApp(home: SetupScreen()));
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('setup-progress-text')), findsOneWidget);
      expect(find.textContaining('50'), findsWidgets);
      expect(find.byKey(const Key('setup-cancel-button')), findsOneWidget);
    });

    testWidgets('shows retry button on error', (tester) async {
      final repo = FakeModelRepository();
      final controller = register(repo);
      controller.status.value = ModelStatus.error;
      controller.errorMessage.value = '다운로드 실패: net';

      await tester.pumpWidget(const GetMaterialApp(home: SetupScreen()));
      await tester.pump();

      expect(find.byKey(const Key('setup-retry-button')), findsOneWidget);
      expect(find.textContaining('다운로드 실패'), findsOneWidget);
    });
  }
  ```

- [ ] **7.2 — run-to-fail:**

  ```bash
  flutter test test/presentation/setup/setup_screen_test.dart
  ```

  기대: 컴파일 실패 — `setup_screen.dart` / `SetupScreen` 미정의.

- [ ] **7.3 — 최소 구현:** `lib/presentation/setup/setup_screen.dart`

  ```dart
  import 'package:flutter/material.dart';
  import 'package:get/get.dart';

  import '../../domain/entities/model_status.dart';
  import 'setup_controller.dart';

  /// Model setup screen: in-app download with progress, cancel, and retry.
  /// Expects a [SetupController] to already be registered in GetX DI
  /// (see `registerModelDeps()` / the route binding).
  class SetupScreen extends StatelessWidget {
    const SetupScreen({super.key});

    String _mb(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(0);

    @override
    Widget build(BuildContext context) {
      final c = Get.find<SetupController>();
      final colorScheme = Theme.of(context).colorScheme;

      return Scaffold(
        appBar: AppBar(
          title: const Text('모델 설정'),
          centerTitle: true,
          backgroundColor: colorScheme.primaryContainer,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.smart_toy_outlined,
                  size: 80, color: colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                '번역 모델 설정',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '한일 번역을 위한 온디바이스 Gemma 모델을 내려받습니다.\n'
                'Wi-Fi 환경을 권장합니다.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Obx(() => _StatusSection(controller: c, mb: _mb)),
            ],
          ),
        ),
      );
    }
  }

  class _StatusSection extends StatelessWidget {
    final SetupController controller;
    final String Function(int) mb;
    const _StatusSection({required this.controller, required this.mb});

    @override
    Widget build(BuildContext context) {
      final c = controller;
      switch (c.status.value) {
        case ModelStatus.downloading:
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: c.totalBytes.value > 0
                    ? LinearProgressIndicator(value: c.fraction, minHeight: 10)
                    : const LinearProgressIndicator(minHeight: 10),
              ),
              const SizedBox(height: 12),
              Text(
                key: const Key('setup-progress-text'),
                c.totalBytes.value > 0
                    ? '${mb(c.receivedBytes.value)} MB / '
                        '${mb(c.totalBytes.value)} MB '
                        '(${(c.fraction * 100).toStringAsFixed(0)}%)'
                    : '다운로드 준비 중...',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                key: const Key('setup-cancel-button'),
                onPressed: c.cancel,
                icon: const Icon(Icons.close),
                label: const Text('취소'),
              ),
            ],
          );

        case ModelStatus.error:
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  c.errorMessage.value.isEmpty
                      ? '오류가 발생했습니다.'
                      : c.errorMessage.value,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red[700], fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('setup-retry-button'),
                onPressed: c.retry,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
              ),
            ],
          );

        case ModelStatus.loaded:
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );

        case ModelStatus.notDownloaded:
        case ModelStatus.downloaded:
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  key: const Key('setup-download-button'),
                  onPressed: c.isBusy.value ? null : c.startDownload,
                  icon: const Icon(Icons.download),
                  label: const Text('모델 다운로드'),
                ),
              ),
            ],
          );
      }
    }
  }
  ```

  > Dart 3 sealed/exhaustive `switch`로 `ModelStatus` 전 상태를 처리한다(누락 시 컴파일 에러). `_StatusSection`을 `Obx`로 감싸 반응형 갱신.

- [ ] **7.4 — run-to-pass:**

  ```bash
  flutter test test/presentation/setup/setup_screen_test.dart
  ```

  기대: `All tests passed!` (3 widget tests).

- [ ] **7.5 — commit:**

  ```bash
  git add lib/presentation/setup/setup_screen.dart test/presentation/setup/setup_screen_test.dart
  git commit -m "feat: add SetupScreen with progress, cancel, retry UI"
  ```

---

## Task 8: `registerModelDeps()` — DI 등록 함수

**Files:**
- Create: `lib/app/model_deps.dart`
- Test: `test/app/model_deps_test.dart`

> `app/bindings.dart`/`app/routes.dart`는 건드리지 않는다. 이 함수만 노출하고 plan 05가 `AppBinding`에서 호출한다. 실제 `InferenceService` 구현(plan 01)이 DI에 먼저 등록돼 있어야 하므로, 이 함수는 `InferenceService`를 `Get.find()`로 **조회**한다(직접 생성하지 않음).

- [ ] **8.1 — 실패 테스트 작성:** `test/app/model_deps_test.dart`

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:get/get.dart';
  import 'package:translate_ko_jp/app/model_deps.dart';
  import 'package:translate_ko_jp/data/repositories/model_repository.dart';
  import 'package:translate_ko_jp/data/services/inference_service.dart';
  import 'package:translate_ko_jp/domain/usecases/ensure_model_ready.dart';
  import 'package:translate_ko_jp/presentation/setup/setup_controller.dart';

  import '../fakes/fake_inference_service_model.dart';

  void main() {
    setUp(() => Get.reset());
    tearDown(() => Get.reset());

    test('registers repository, use case, and controller', () {
      // InferenceService is owned/registered by plan 01; provide a fake here.
      Get.put<InferenceService>(FakeInferenceServiceModel());

      registerModelDeps();

      expect(Get.find<ModelRepository>(), isA<ModelRepository>());
      expect(Get.find<EnsureModelReady>(), isA<EnsureModelReady>());
      expect(Get.find<SetupController>(), isA<SetupController>());
    });
  }
  ```

- [ ] **8.2 — run-to-fail:**

  ```bash
  flutter test test/app/model_deps_test.dart
  ```

  기대: 컴파일 실패 — `model_deps.dart` / `registerModelDeps` 미정의.

- [ ] **8.3 — 최소 구현:** `lib/app/model_deps.dart`

  ```dart
  import 'package:get/get.dart';

  import '../data/repositories/model_repository.dart';
  import '../data/services/inference_service.dart';
  import '../data/services/model_config.dart';
  import '../data/services/model_download_service.dart';
  import '../data/services/model_download_service_impl.dart';
  import '../domain/usecases/ensure_model_ready.dart';
  import '../presentation/setup/setup_controller.dart';
  import 'routes.dart';

  /// Registers model-management dependencies. Call from AppBinding (plan 05).
  ///
  /// Precondition: an [InferenceService] is already registered in GetX DI
  /// (owned by plan 01). This function only looks it up.
  void registerModelDeps({ModelConfig config = const ModelConfig.gemmaE2B()}) {
    Get.lazyPut<ModelDownloadService>(() => ModelDownloadServiceImpl());

    Get.lazyPut<ModelRepository>(
      () => ModelRepositoryImpl(
        inference: Get.find<InferenceService>(),
        downloadService: Get.find<ModelDownloadService>(),
        config: config,
      ),
    );

    Get.lazyPut<EnsureModelReady>(
      () => EnsureModelReady(Get.find<ModelRepository>()),
    );

    Get.lazyPut<SetupController>(
      () => SetupController(
        repository: Get.find<ModelRepository>(),
        ensureModelReady: Get.find<EnsureModelReady>(),
        onReady: () => Get.offAllNamed(Routes.translation),
      ),
    );
  }
  ```

  > `Routes.translation`은 foundation(`lib/app/routes.dart`)이 정의한 상수를 참조한다. 이 파일은 `routes.dart`를 import만 하고 수정하지 않는다.

- [ ] **8.4 — run-to-pass:**

  ```bash
  flutter test test/app/model_deps_test.dart
  ```

  기대: `All tests passed!` (1 test).

  > **주의:** 이 테스트가 `Routes.translation`을 참조하므로 plan 00의 `lib/app/routes.dart`에 `Routes.translation`이 정의돼 있어야 한다. 없으면 plan 00 미완료 — plan 00을 먼저 끝낼 것.

- [ ] **8.5 — commit:**

  ```bash
  git add lib/app/model_deps.dart test/app/model_deps_test.dart
  git commit -m "feat: add registerModelDeps DI wiring for model-management flow"
  ```

---

## Task 9: 전체 회귀 검증

**Files:** (없음 — 검증만)

- [ ] **9.1 — 전체 테스트 (run):**

  ```bash
  flutter test
  ```

  기대: 이 플로우의 모든 테스트 통과. (plan 00/01의 테스트도 함께 통과해야 한다. 실패 시 이 플로우 범위 밖 — 의존 plan 확인.)

- [ ] **9.2 — 정적 분석 (run):**

  ```bash
  flutter analyze
  ```

  기대: `No issues found!` (이 플로우가 만든 `lib/`/`test/` 파일에 한해).

- [ ] **9.3 — 최종 커밋(필요 시):**

  ```bash
  git add -A
  git commit -m "test: verify model-management flow green" --allow-empty
  ```

---

## 완료 기준 (Definition of Done)

- [ ] `pubspec.yaml`에 `crypto` 추가 + `flutter pub get` 성공.
- [ ] `ModelConfig` — 기본 Gemma 4 E2B `.task` URL/파일명/체크섬/헤더 보유, 값 동등성 동작.
- [ ] `ModelDownloadServiceImpl`가 계약(`ModelDownloadService`)을 정확히 구현: 진행률 스트리밍, `.part`→dest 리네임, HTTP Range 재개, 취소, SHA-256 검증(불일치 시 throw + 파일 미생성).
- [ ] 다운로드 테스트가 `MockClient`로 진행률/체크섬 불일치/정상 체크섬/Range 재개/취소를 모두 커버하고 통과.
- [ ] `ModelRepositoryImpl` — `currentStatus()`가 `InferenceService.modelExists`+`isLoaded`로 `ModelStatus` 계산, `download()`가 설정값 위임, `load()`가 `Result<void>` 반환 + 에러 `ModelFailure` 매핑(Dart 3 sealed switch 사용).
- [ ] `EnsureModelReady` — notDownloaded→needsDownload, downloaded→load 후 ready, 로드 실패→Err 전파.
- [ ] `SetupController` — `.obs` 반응형 상태, 다운로드 진행률/취소/재시도/로드/네비게이션(`onReady` 콜백) 조율.
- [ ] `SetupScreen` — 진행률 바, MB 다운로드/전체 표시, 취소/재시도 버튼, 상태 텍스트. `ModelStatus` 전 상태 exhaustive 처리.
- [ ] `registerModelDeps()` — Repository/UseCase/Controller 등록, `InferenceService`는 조회, `Routes.translation`로 네비게이션. `bindings.dart`/`routes.dart` 미수정.
- [ ] 테스트 fake(`FakeInferenceServiceModel`)는 모델 전용 파일명으로 plan 01과 충돌하지 않음.
- [ ] 네이티브 코드 미작성, `MediaPipeInferenceService` 미구현.
- [ ] `flutter test` 및 `flutter analyze` 그린.
