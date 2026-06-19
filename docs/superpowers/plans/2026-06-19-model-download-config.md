# Model Download Config (HF Auth + dart-define) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make model download source configurable at build time via `--dart-define`, support Hugging Face downloads with a Bearer token injected as a header (token NEVER hardcoded), and warn when checksum verification is skipped.

**Architecture:** `ModelConfig` gains two new factories (`huggingFace` and `fromEnvironment`) that derive headers/filename from arguments. `registerModelDeps` defaults to `ModelConfig.fromEnvironment()` instead of the hardcoded `gemmaE2B()`. The download service emits a `debugPrint` warning when `sha256 == null`.

**Tech Stack:** Flutter/Dart, GetX DI, `flutter/foundation.dart` (debugPrint), `--dart-define` compile-time env vars.

---

## File Map

| File | Action | What changes |
|------|--------|-------------|
| `lib/data/services/model_config.dart` | Modify | Add `ModelConfig.huggingFace(...)` named constructor and `ModelConfig.fromEnvironment()` factory |
| `lib/data/services/model_download_service_impl.dart` | Modify | Add `else { debugPrint(...) }` branch when `sha256 == null`; add `flutter/foundation.dart` import |
| `lib/app/model_deps.dart` | Modify | Change default parameter from `ModelConfig.gemmaE2B()` to nullable `ModelConfig?`, use `config ?? ModelConfig.fromEnvironment()` |
| `test/data/services/model_config_test.dart` | Modify | Add tests for `huggingFace` constructor and `fromEnvironment` factory |
| `test/app/model_deps_test.dart` | No change needed | Already passes explicit `config:` (none); `registerModelDeps()` with no args still works |
| `README.md` | Modify | Add "## 모델 설정 (Model setup)" section |

---

### Task 1: Add `ModelConfig.huggingFace` tests (TDD: failing first)

**Files:**
- Modify: `test/data/services/model_config_test.dart`

- [ ] **Step 1: Add the failing tests for `ModelConfig.huggingFace`**

Open `test/data/services/model_config_test.dart` and append a new group inside `main()` after the existing `ModelConfig` group:

```dart
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
```

- [ ] **Step 2: Run tests to confirm they fail (factory not yet defined)**

```
flutter test test/data/services/model_config_test.dart
```

Expected output: FAIL — `Error: The method 'ModelConfig.huggingFace' isn't defined.`

---

### Task 2: Implement `ModelConfig.huggingFace` and `ModelConfig.fromEnvironment`

**Files:**
- Modify: `lib/data/services/model_config.dart`

- [ ] **Step 1: Add the two new constructors/factories**

After the existing `const ModelConfig.gemmaE2B()` block and before `@override bool operator ==`, insert:

```dart
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
  required String url,
  String? sha256,
  String? token,
  String? fileName,
}) : url = url,
     sha256 = sha256,
     headers = (token != null && token.isNotEmpty)
         ? {'Authorization': 'Bearer $token'}
         : null,
     fileName = (fileName != null && fileName.isNotEmpty)
         ? fileName
         : () {
             final segment = url.split('/').last;
             return segment.isNotEmpty ? segment : 'gemma-4-e2b.task';
           }();

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
```

**Important Dart note:** The named constructor `ModelConfig.huggingFace` has a `fileName` field that requires a non-const initializer (the lambda IIFE). Since the primary constructor is `const`, the named constructor must NOT be `const`. Dart allows non-const named constructors on a class that also has `const` constructors. The `factory` keyword on `fromEnvironment` is also non-const, which is valid.

- [ ] **Step 2: Run model_config tests to confirm they pass**

```
flutter test test/data/services/model_config_test.dart
```

Expected: All tests PASS (including the 3 existing and the 10 new ones).

- [ ] **Step 3: Commit**

```
git add lib/data/services/model_config.dart test/data/services/model_config_test.dart
git commit -m "feat: add ModelConfig.huggingFace and fromEnvironment factories"
```

---

### Task 3: Add `debugPrint` warning when checksum is skipped

**Files:**
- Modify: `lib/data/services/model_download_service_impl.dart`

- [ ] **Step 1: Add `flutter/foundation.dart` import**

At the top of the file, after the existing `import 'dart:io';` line, add:

```dart
import 'package:flutter/foundation.dart';
```

- [ ] **Step 2: Add `else` branch for the null-sha256 case**

Find the checksum block (around line 146–153):

```dart
// Checksum verification over the full assembled part file.
if (sha256 != null) {
  final digest = await _sha256OfFile(partFile);
  if (digest != sha256.toLowerCase()) {
    await _safeDelete(partFile);
    throw ModelDownloadException(
        'checksum mismatch: expected $sha256, got $digest');
  }
}
```

Replace it with:

```dart
// Checksum verification over the full assembled part file.
if (sha256 != null) {
  final digest = await _sha256OfFile(partFile);
  if (digest != sha256.toLowerCase()) {
    await _safeDelete(partFile);
    throw ModelDownloadException(
        'checksum mismatch: expected $sha256, got $digest');
  }
} else {
  debugPrint('[ModelDownload] WARNING: no SHA-256 provided; '
      'skipping checksum verification for $destPath');
}
```

- [ ] **Step 3: Run download service tests**

```
flutter test test/data/services/model_download_service_impl_test.dart
```

Expected: All 5 existing tests PASS. The warning now prints in the test that downloads without sha256, which is fine (debugPrint is a no-op in test unless you check output).

- [ ] **Step 4: Commit**

```
git add lib/data/services/model_download_service_impl.dart
git commit -m "feat: warn via debugPrint when SHA-256 checksum is skipped"
```

---

### Task 4: Update `registerModelDeps` to use `fromEnvironment` by default

**Files:**
- Modify: `lib/app/model_deps.dart`

- [ ] **Step 1: Change function signature and body**

Replace:

```dart
/// Registers model-management dependencies. Call from AppBinding (plan 05).
///
/// Precondition: an [InferenceService] is already registered in GetX DI
/// (owned by plan 01). This function only looks it up.
void registerModelDeps({ModelConfig config = const ModelConfig.gemmaE2B()}) {
  Get.lazyPut<ModelDownloadService>(() => ModelDownloadServiceImpl(), fenix: true);

  Get.lazyPut<ModelRepository>(
    () => ModelRepositoryImpl(
      inference: Get.find<InferenceService>(),
      downloadService: Get.find<ModelDownloadService>(),
      config: config,
    ),
    fenix: true,
  );
```

With:

```dart
/// Registers model-management dependencies. Call from AppBinding (plan 05).
///
/// Precondition: an [InferenceService] is already registered in GetX DI
/// (owned by plan 01). This function only looks it up.
///
/// [config] defaults to [ModelConfig.fromEnvironment()], which reads
/// `MODEL_URL`, `MODEL_SHA256`, and `HF_TOKEN` from `--dart-define` values
/// supplied at build/run time. Pass an explicit config in tests.
void registerModelDeps({ModelConfig? config}) {
  final cfg = config ?? ModelConfig.fromEnvironment();

  Get.lazyPut<ModelDownloadService>(() => ModelDownloadServiceImpl(), fenix: true);

  Get.lazyPut<ModelRepository>(
    () => ModelRepositoryImpl(
      inference: Get.find<InferenceService>(),
      downloadService: Get.find<ModelDownloadService>(),
      config: cfg,
    ),
    fenix: true,
  );
```

- [ ] **Step 2: Run `model_deps_test.dart` to verify it still passes**

```
flutter test test/app/model_deps_test.dart
```

Expected: PASS. The test calls `registerModelDeps()` with no args, which now calls `ModelConfig.fromEnvironment()` — still a valid `ModelConfig`.

- [ ] **Step 3: Commit**

```
git add lib/app/model_deps.dart
git commit -m "feat: default registerModelDeps to ModelConfig.fromEnvironment()"
```

---

### Task 5: Add README usage section

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add model setup section**

Append the following to `README.md` (after the existing content):

```markdown
## 모델 설정 (Model setup)

모델 다운로드 소스는 빌드/실행 시 `--dart-define` 플래그로 설정합니다.

The model download source is configured at build/run time via `--dart-define` flags — no secrets are ever hardcoded.

```sh
flutter run \
  --dart-define=MODEL_URL=https://huggingface.co/<org>/<repo>/resolve/main/<file>.task \
  --dart-define=HF_TOKEN=<your_hf_token> \
  --dart-define=MODEL_SHA256=<optional_lowercase_hex_sha256>
```

| Variable | Required | Description |
|----------|----------|-------------|
| `MODEL_URL` | No (has default) | Full HTTPS resolve URL of the `.task` model file. Defaults to a best-guess Hugging Face URL — **verify the exact path before release**. |
| `HF_TOKEN` | For private repos | Hugging Face API token. Injected as `Authorization: Bearer <token>` header. **Never commit this token.** |
| `MODEL_SHA256` | Recommended | Lowercase hex SHA-256 of the downloaded file. If omitted, checksum verification is skipped and a warning is logged. |

For release builds, supply these via CI secrets (e.g. `--dart-define=HF_TOKEN=$HF_TOKEN`).
```

- [ ] **Step 2: Commit**

```
git add README.md
git commit -m "docs: add model setup section with dart-define usage"
```

---

### Task 6: Full verification pass

**Files:** None changed — run test suite and analyzer.

- [ ] **Step 1: Run all targeted tests**

```
flutter test test/data/services/model_config_test.dart test/data/services/model_download_service_impl_test.dart test/app/model_deps_test.dart test/data/repositories/model_repository_test.dart test/presentation/setup
```

Expected: All PASS.

- [ ] **Step 2: Run analyzer on changed files**

```
flutter analyze lib/data/services/model_config.dart lib/data/services/model_download_service_impl.dart lib/app/model_deps.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Squash/combine into final commit if desired**

The spec requests a single commit message: `feat: configurable model source via dart-define with Hugging Face token header`

If the three feature commits should be squashed:

```
git log --oneline -5
# decide if squash is desired; if yes:
git rebase -i HEAD~3
# (mark commits 2, 3 as 'squash'; edit message to the spec-requested message)
```

Or simply leave the granular commits as-is — the final commit covering all changes is sufficient.

---

## Self-Review: Spec Coverage Checklist

| Spec requirement | Task |
|-----------------|------|
| `ModelConfig.huggingFace(...)` named constructor | Task 2 |
| `headers` set from token (null/empty → null) | Task 2 |
| `fileName` derived from URL last segment, fallback `gemma-4-e2b.task` | Task 2 |
| `ModelConfig.fromEnvironment()` reads MODEL_URL, MODEL_SHA256, HF_TOKEN | Task 2 |
| Default URL documented with caveat to verify | Task 2 (doc comment) |
| `gemmaE2B()` unchanged | Not touched — existing tests confirm |
| `registerModelDeps` signature → `{ModelConfig? config}` | Task 4 |
| `registerModelDeps` default uses `fromEnvironment()` | Task 4 |
| `debugPrint` warning when sha256 is null | Task 3 |
| Tests for token header (non-empty, null, empty) | Task 1 |
| Tests for fileName derivation (URL segment, explicit, empty fallback) | Task 1 |
| Tests for `fromEnvironment()` (url non-empty, sha256 null, headers null) | Task 1 |
| Token NEVER hardcoded | Enforced by `String.fromEnvironment` only |
| README model setup section | Task 5 |
| All targeted tests pass | Task 6 |
| Analyzer clean | Task 6 |
| Final commit with spec message | Task 6 |
