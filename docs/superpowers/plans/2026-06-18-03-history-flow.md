# 번역 히스토리 플로우 (History Flow) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist translation results in a local sqflite database and expose a newest-first history screen with per-item copy / TTS replay / delete and an app-bar clear-all, fully covered by off-device tests.

**Architecture:** Follows the project MVVM seam (View → ViewModel → UseCase → Repository → Service). `SqfliteHistoryStore` implements the foundation `HistoryStore` interface over a `translations` table; `HistoryRepository` wraps it returning `Result<T>` and maps exceptions to `StorageFailure`; four callable UseCases drive a GetX `HistoryController`; `HistoryScreen` renders the reactive list. All external dependencies are interfaces, so tests inject Fakes (`FakeHistoryStore`, `FakeHistoryRepository`, `FakeTtsService`) and the store itself is tested with `sqflite_common_ffi` in-memory.

**Tech Stack:** Flutter, Dart 3, GetX, sqflite, sqflite_common_ffi, path, flutter_test

---

## 전제 / 계약 (Foundation에서 확정됨 — 그대로 사용)

> 아래 타입은 **plan 00 (foundation)** 가 이미 만들어 둔 것이다. 이 플랜은 절대 수정하지 않고 import만 한다. 시그니처는 INDEX의 "공유 계약"과 **정확히** 일치해야 한다.

- `lib/core/language.dart` — `enum Language { ko, ja }` (`name` → `"ko"` / `"ja"`, `ttsCode`, `opposite` 등).
- `lib/core/failure.dart` — `sealed class Failure` + `StorageFailure`.
- `lib/core/result.dart` — `sealed class Result<T>` = `Ok<T>` | `Err<T>`.
- `lib/domain/entities/language_direction.dart` — `LanguageDirection{ from, to }`.
- `lib/domain/entities/translation_result.dart` — `TranslationResult{ id?, sourceText, translatedText, direction, createdAt }`, `copyWith({int? id})`.
- `lib/data/services/history_store.dart` — `abstract interface class HistoryStore`:
  ```dart
  Future<int> insert(TranslationResult result);
  Future<List<TranslationResult>> getAll(); // newest first
  Future<void> delete(int id);
  Future<void> clear();
  ```
- `lib/data/services/tts_service.dart` — `abstract interface class TtsService`:
  ```dart
  Future<void> initialize();
  Future<void> speak({required String text, required Language language});
  Future<void> stop();
  ```
- `lib/data/repositories/history_repository.dart` interface 시그니처 (INDEX):
  ```dart
  abstract interface class HistoryRepository {
    Future<Result<int>> save(TranslationResult result);
    Future<Result<List<TranslationResult>>> getAll();
    Future<Result<void>> delete(int id);
    Future<Result<void>> clear();
  }
  ```

> **주의:** `Failure`/`Result`가 sealed이므로 Repository/Controller에서 `Result`를 풀 때는 Dart 3 `switch`(sealed exhaustive)를 사용한다.

### 경계 (BOUNDARIES — 반드시 지킬 것)

- `lib/app/bindings.dart`, `lib/app/routes.dart`는 **건드리지 않는다** (foundation 소유, `Routes.history` 이미 존재).
- 히스토리 DI는 별도 파일 `lib/app/history_deps.dart`의 `registerHistoryDeps()`로만 노출한다.
- `TtsServiceImpl`, 네이티브 코드, 번역 컨트롤러 등 히스토리 범위 밖은 구현하지 않는다. TTS 재생은 `TtsService` 인터페이스에만 의존하고 테스트는 `FakeTtsService` 사용.
- plan 01의 파일(`translation_controller.dart` 등)을 **수정하지 않는다**. SaveTranslation 실제 연결은 plan 05.

---

## Task 0 — pubspec 의존성 추가

**Files:** `pubspec.yaml`

- [ ] 1. `dependencies`에 `sqflite`와 `path` 추가, `dev_dependencies`에 `sqflite_common_ffi` 추가:

```yaml
dependencies:
  flutter:
    sdk: flutter
  speech_to_text: ^7.0.0
  flutter_tts: ^4.2.0
  permission_handler: ^11.3.0
  get: ^4.6.6
  file_picker: ^8.0.0
  path_provider: ^2.1.0
  http: ^1.2.0
  sqflite: ^2.3.3
  path: ^1.9.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  sqflite_common_ffi: ^2.3.3
```

- [ ] 2. Run: `flutter pub get`
  - 기대: `Got dependencies!` (또는 `Changed N dependencies!`), 에러 없음.
- [ ] 3. Commit: `chore: add sqflite, path, sqflite_common_ffi for history flow`

---

## Task 1 — SqfliteHistoryStore: 라운드트립(insert/getAll) (FFI 인메모리)

**Files:** `test/data/services/sqflite_history_store_test.dart`, `lib/data/services/sqflite_history_store.dart`

- [ ] 1. **Write the failing test** — `test/data/services/sqflite_history_store_test.dart` (sqflite_common_ffi 실제 셋업: `sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi` + `inMemoryDatabasePath`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:translate_ko_jp/core/language.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/data/services/sqflite_history_store.dart';

void main() {
  setUpAll(() {
    // Initialize FFI so sqflite runs off-device (desktop/test VM).
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqfliteHistoryStore store;

  setUp(() async {
    // Fresh in-memory DB per test → fully isolated.
    store = SqfliteHistoryStore();
    await store.open(path: inMemoryDatabasePath);
  });

  tearDown(() async {
    await store.close();
  });

  TranslationResult sample({
    String source = '안녕하세요',
    String translated = 'こんにちは',
    LanguageDirection? dir,
    DateTime? at,
  }) {
    return TranslationResult(
      sourceText: source,
      translatedText: translated,
      direction: dir ?? LanguageDirection.koToJa(),
      createdAt: at ?? DateTime.fromMillisecondsSinceEpoch(1000),
    );
  }

  test('insert returns a positive autoincrement id', () async {
    final id = await store.insert(sample());
    expect(id, greaterThan(0));
  });

  test('getAll round-trips fields and reconstructs direction', () async {
    await store.insert(sample(
      source: '안녕',
      translated: 'やあ',
      dir: LanguageDirection.koToJa(),
      at: DateTime.fromMillisecondsSinceEpoch(5000),
    ));

    final all = await store.getAll();

    expect(all, hasLength(1));
    final row = all.first;
    expect(row.id, isNotNull);
    expect(row.sourceText, '안녕');
    expect(row.translatedText, 'やあ');
    expect(row.direction.from, Language.ko);
    expect(row.direction.to, Language.ja);
    expect(row.createdAt, DateTime.fromMillisecondsSinceEpoch(5000));
  });

  test('getAll returns newest first (ORDER BY created_at DESC)', () async {
    await store.insert(sample(source: 'old', at: DateTime.fromMillisecondsSinceEpoch(1000)));
    await store.insert(sample(source: 'mid', at: DateTime.fromMillisecondsSinceEpoch(2000)));
    await store.insert(sample(source: 'new', at: DateTime.fromMillisecondsSinceEpoch(3000)));

    final all = await store.getAll();

    expect(all.map((r) => r.sourceText).toList(), ['new', 'mid', 'old']);
  });

  test('stores ja->ko direction and reconstructs it', () async {
    await store.insert(sample(dir: LanguageDirection.jaToKo()));
    final row = (await store.getAll()).first;
    expect(row.direction.from, Language.ja);
    expect(row.direction.to, Language.ko);
  });
}
```

- [ ] 2. **Run to fail**: `flutter test test/data/services/sqflite_history_store_test.dart`
  - 기대: 컴파일 실패 — `Error: ... 'SqfliteHistoryStore' isn't defined` / `Target of URI doesn't exist: '.../sqflite_history_store.dart'`.
- [ ] 3. **Minimal implementation** — `lib/data/services/sqflite_history_store.dart` (전체 코드):

```dart
import 'package:sqflite/sqflite.dart';

import '../../core/language.dart';
import '../../domain/entities/language_direction.dart';
import '../../domain/entities/translation_result.dart';
import 'history_store.dart';

/// sqflite-backed [HistoryStore].
///
/// Table `translations`:
///   id INTEGER PRIMARY KEY AUTOINCREMENT,
///   source_text TEXT,
///   translated_text TEXT,
///   source_lang TEXT,   -- Language.name ("ko" | "ja")
///   target_lang TEXT,   -- Language.name ("ko" | "ja")
///   created_at INTEGER  -- millisecondsSinceEpoch
class SqfliteHistoryStore implements HistoryStore {
  static const String tableName = 'translations';
  static const int _schemaVersion = 1;

  Database? _db;

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('SqfliteHistoryStore.open() must be called first');
    }
    return db;
  }

  /// Opens (and creates if needed) the database at [path].
  /// In tests pass `inMemoryDatabasePath`; in app pass a real file path.
  Future<void> open({required String path}) async {
    _db = await openDatabase(
      path,
      version: _schemaVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_text TEXT NOT NULL,
            translated_text TEXT NOT NULL,
            source_lang TEXT NOT NULL,
            target_lang TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  @override
  Future<int> insert(TranslationResult result) {
    return _database.insert(tableName, _toRow(result));
  }

  @override
  Future<List<TranslationResult>> getAll() async {
    final rows = await _database.query(
      tableName,
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> delete(int id) async {
    await _database.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> clear() async {
    await _database.delete(tableName);
  }

  Map<String, Object?> _toRow(TranslationResult r) {
    return <String, Object?>{
      if (r.id != null) 'id': r.id,
      'source_text': r.sourceText,
      'translated_text': r.translatedText,
      'source_lang': r.direction.from.name,
      'target_lang': r.direction.to.name,
      'created_at': r.createdAt.millisecondsSinceEpoch,
    };
  }

  TranslationResult _fromRow(Map<String, Object?> row) {
    return TranslationResult(
      id: row['id'] as int?,
      sourceText: row['source_text'] as String,
      translatedText: row['translated_text'] as String,
      direction: LanguageDirection(
        from: _langFromName(row['source_lang'] as String),
        to: _langFromName(row['target_lang'] as String),
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }

  Language _langFromName(String name) {
    return Language.values.firstWhere((l) => l.name == name);
  }
}
```

- [ ] 4. **Run to pass**: `flutter test test/data/services/sqflite_history_store_test.dart`
  - 기대: `All tests passed!` (4 tests).
- [ ] 5. Commit: `feat: SqfliteHistoryStore insert/getAll with FFI-tested round-trip`

---

## Task 2 — SqfliteHistoryStore: delete & clear

**Files:** `test/data/services/sqflite_history_store_test.dart` (append), `lib/data/services/sqflite_history_store.dart` (already implemented — verify)

- [ ] 1. **Add failing tests** — append inside `main()` of `test/data/services/sqflite_history_store_test.dart`:

```dart
  test('delete removes only the matching row', () async {
    final keepId = await store.insert(sample(source: 'keep'));
    final dropId = await store.insert(sample(source: 'drop'));

    await store.delete(dropId);

    final all = await store.getAll();
    expect(all, hasLength(1));
    expect(all.single.id, keepId);
    expect(all.single.sourceText, 'keep');
  });

  test('delete with unknown id is a no-op', () async {
    await store.insert(sample());
    await store.delete(999999);
    expect(await store.getAll(), hasLength(1));
  });

  test('clear removes all rows', () async {
    await store.insert(sample(source: 'a'));
    await store.insert(sample(source: 'b'));

    await store.clear();

    expect(await store.getAll(), isEmpty);
  });
```

- [ ] 2. **Run to (likely) pass**: `flutter test test/data/services/sqflite_history_store_test.dart`
  - 기대: `delete`/`clear`가 Task 1에서 이미 구현됐으므로 `All tests passed!` (7 tests). 만약 실패하면 store의 `delete`/`clear` SQL을 수정해 통과시킨다.
- [ ] 3. Commit: `test: cover SqfliteHistoryStore delete and clear`

---

## Task 3 — Fakes: FakeHistoryStore, FakeHistoryRepository, FakeTtsService

**Files:** `test/fakes/fake_history_store.dart`, `test/fakes/fake_history_repository.dart`, `test/fakes/fake_tts_service.dart`

> 순수 fake라 별도 단위 테스트는 없다. 이후 Task의 테스트가 이 fake들을 사용하면서 실질 검증된다. 컴파일만 보장하면 된다.

- [ ] 1. **Create** `test/fakes/fake_history_store.dart`:

```dart
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/data/services/history_store.dart';

/// In-memory [HistoryStore] for tests. Assigns incrementing ids and
/// returns newest-first by createdAt (ties broken by insertion order).
class FakeHistoryStore implements HistoryStore {
  final List<TranslationResult> _rows = <TranslationResult>[];
  int _nextId = 1;

  bool throwOnInsert = false;
  bool throwOnGetAll = false;
  bool throwOnDelete = false;
  bool throwOnClear = false;

  @override
  Future<int> insert(TranslationResult result) async {
    if (throwOnInsert) throw Exception('insert failed');
    final id = _nextId++;
    _rows.add(result.copyWith(id: id));
    return id;
  }

  @override
  Future<List<TranslationResult>> getAll() async {
    if (throwOnGetAll) throw Exception('getAll failed');
    final sorted = List<TranslationResult>.from(_rows)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  @override
  Future<void> delete(int id) async {
    if (throwOnDelete) throw Exception('delete failed');
    _rows.removeWhere((r) => r.id == id);
  }

  @override
  Future<void> clear() async {
    if (throwOnClear) throw Exception('clear failed');
    _rows.clear();
  }
}
```

- [ ] 2. **Create** `test/fakes/fake_history_repository.dart`:

```dart
import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/data/repositories/history_repository.dart';

/// Scriptable [HistoryRepository] fake for UseCase/Controller tests.
class FakeHistoryRepository implements HistoryRepository {
  final List<TranslationResult> entries = <TranslationResult>[];
  int _nextId = 1;

  // Records of calls for assertions.
  final List<TranslationResult> savedArgs = <TranslationResult>[];
  final List<int> deletedIds = <int>[];
  int clearCount = 0;

  // Force failures for error-path tests.
  Failure? failSave;
  Failure? failGetAll;
  Failure? failDelete;
  Failure? failClear;

  @override
  Future<Result<int>> save(TranslationResult result) async {
    savedArgs.add(result);
    if (failSave != null) return Err(failSave!);
    final id = _nextId++;
    entries.add(result.copyWith(id: id));
    return Ok(id);
  }

  @override
  Future<Result<List<TranslationResult>>> getAll() async {
    if (failGetAll != null) return Err(failGetAll!);
    final sorted = List<TranslationResult>.from(entries)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Ok(sorted);
  }

  @override
  Future<Result<void>> delete(int id) async {
    deletedIds.add(id);
    if (failDelete != null) return Err(failDelete!);
    entries.removeWhere((e) => e.id == id);
    return const Ok(null);
  }

  @override
  Future<Result<void>> clear() async {
    clearCount++;
    if (failClear != null) return Err(failClear!);
    entries.clear();
    return const Ok(null);
  }
}
```

- [ ] 3. **Create** `test/fakes/fake_tts_service.dart`:

```dart
import 'package:translate_ko_jp/core/language.dart';
import 'package:translate_ko_jp/data/services/tts_service.dart';

class SpokenUtterance {
  final String text;
  final Language language;
  const SpokenUtterance(this.text, this.language);
}

/// Records what was spoken so tests can assert TTS replay.
class FakeTtsService implements TtsService {
  bool initialized = false;
  int stopCount = 0;
  final List<SpokenUtterance> spoken = <SpokenUtterance>[];

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> speak({required String text, required Language language}) async {
    spoken.add(SpokenUtterance(text, language));
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}
```

- [ ] 4. **Run** (smoke-compile the fakes via the existing store test, which still passes): `flutter test test/data/services/sqflite_history_store_test.dart`
  - 기대: `All tests passed!` (fakes 아직 미사용이지만 analyzer 경고만 없으면 OK). 선택적으로 `flutter analyze test/fakes`로 컴파일 확인.
- [ ] 5. Commit: `test: add FakeHistoryStore, FakeHistoryRepository, FakeTtsService`

---

## Task 4 — HistoryRepository 구현 (Store → Result, 예외 → StorageFailure)

**Files:** `test/data/repositories/history_repository_test.dart`, `lib/data/repositories/history_repository.dart`

> INDEX는 `history_repository.dart`에 인터페이스 시그니처를 둔다. foundation이 인터페이스를 이미 정의했는지에 따라 두 경우가 있다:
> - **이미 인터페이스가 존재하면**: 같은 파일에 `HistoryRepositoryImpl`을 추가한다 (인터페이스 선언은 수정하지 않음).
> - **아직 없으면**: 같은 파일에 인터페이스 + impl을 함께 둔다.
>
> 아래 구현은 두 경우 모두 커버하도록 인터페이스를 파일 안에 포함하되, foundation이 이미 만들었다면 중복 선언을 제거하고 import만 맞춘다. (한 파일이므로 머지 경계 안전.)

- [ ] 1. **Write the failing test** — `test/data/repositories/history_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/core/language.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/data/repositories/history_repository.dart';

import '../../fakes/fake_history_store.dart';

TranslationResult _sample({DateTime? at}) => TranslationResult(
      sourceText: '안녕',
      translatedText: 'やあ',
      direction: LanguageDirection.koToJa(),
      createdAt: at ?? DateTime.fromMillisecondsSinceEpoch(1000),
    );

void main() {
  late FakeHistoryStore store;
  late HistoryRepository repo;

  setUp(() {
    store = FakeHistoryStore();
    repo = HistoryRepositoryImpl(store);
  });

  group('save', () {
    test('returns Ok(id) on success', () async {
      final result = await repo.save(_sample());
      expect(result, isA<Ok<int>>());
      expect((result as Ok<int>).value, greaterThan(0));
    });

    test('maps store exception to Err(StorageFailure)', () async {
      store.throwOnInsert = true;
      final result = await repo.save(_sample());
      expect(result, isA<Err<int>>());
      expect((result as Err<int>).failure, isA<StorageFailure>());
    });
  });

  group('getAll', () {
    test('returns Ok(list) newest first', () async {
      await store.insert(_sample(at: DateTime.fromMillisecondsSinceEpoch(1000)));
      await store.insert(_sample(at: DateTime.fromMillisecondsSinceEpoch(2000)));

      final result = await repo.getAll();
      expect(result, isA<Ok<List<TranslationResult>>>());
      final list = (result as Ok<List<TranslationResult>>).value;
      expect(list, hasLength(2));
      expect(list.first.createdAt.millisecondsSinceEpoch, 2000);
    });

    test('maps exception to Err(StorageFailure)', () async {
      store.throwOnGetAll = true;
      final result = await repo.getAll();
      expect(result, isA<Err<List<TranslationResult>>>());
      expect((result as Err<List<TranslationResult>>).failure, isA<StorageFailure>());
    });
  });

  group('delete', () {
    test('returns Ok(null) on success', () async {
      final id = await store.insert(_sample());
      final result = await repo.delete(id);
      expect(result, isA<Ok<void>>());
      expect(await store.getAll(), isEmpty);
    });

    test('maps exception to Err(StorageFailure)', () async {
      store.throwOnDelete = true;
      final result = await repo.delete(1);
      expect((result as Err<void>).failure, isA<StorageFailure>());
    });
  });

  group('clear', () {
    test('returns Ok(null) on success', () async {
      await store.insert(_sample());
      final result = await repo.clear();
      expect(result, isA<Ok<void>>());
      expect(await store.getAll(), isEmpty);
    });

    test('maps exception to Err(StorageFailure)', () async {
      store.throwOnClear = true;
      final result = await repo.clear();
      expect((result as Err<void>).failure, isA<StorageFailure>());
    });
  });

  // Sanity: Language.name still maps as the store expects.
  test('Language.name values are stable', () {
    expect(Language.ko.name, 'ko');
    expect(Language.ja.name, 'ja');
  });
}
```

- [ ] 2. **Run to fail**: `flutter test test/data/repositories/history_repository_test.dart`
  - 기대: 컴파일 실패 — `'HistoryRepositoryImpl' isn't defined`.
- [ ] 3. **Minimal implementation** — `lib/data/repositories/history_repository.dart`. (foundation이 이미 인터페이스를 선언했다면 인터페이스 블록을 제거하고 impl만 남긴다.):

```dart
import '../../core/failure.dart';
import '../../core/result.dart';
import '../../domain/entities/translation_result.dart';
import '../services/history_store.dart';

abstract interface class HistoryRepository {
  Future<Result<int>> save(TranslationResult result);
  Future<Result<List<TranslationResult>>> getAll();
  Future<Result<void>> delete(int id);
  Future<Result<void>> clear();
}

class HistoryRepositoryImpl implements HistoryRepository {
  final HistoryStore _store;
  const HistoryRepositoryImpl(this._store);

  @override
  Future<Result<int>> save(TranslationResult result) async {
    try {
      final id = await _store.insert(result);
      return Ok(id);
    } catch (e) {
      return Err(StorageFailure('히스토리 저장에 실패했습니다: $e'));
    }
  }

  @override
  Future<Result<List<TranslationResult>>> getAll() async {
    try {
      final list = await _store.getAll();
      return Ok(list);
    } catch (e) {
      return Err(StorageFailure('히스토리 조회에 실패했습니다: $e'));
    }
  }

  @override
  Future<Result<void>> delete(int id) async {
    try {
      await _store.delete(id);
      return const Ok(null);
    } catch (e) {
      return Err(StorageFailure('히스토리 삭제에 실패했습니다: $e'));
    }
  }

  @override
  Future<Result<void>> clear() async {
    try {
      await _store.clear();
      return const Ok(null);
    } catch (e) {
      return Err(StorageFailure('히스토리 전체 삭제에 실패했습니다: $e'));
    }
  }
}
```

- [ ] 4. **Run to pass**: `flutter test test/data/repositories/history_repository_test.dart`
  - 기대: `All tests passed!`.
- [ ] 5. Commit: `feat: HistoryRepositoryImpl mapping store errors to StorageFailure`

---

## Task 5 — UseCase: SaveTranslation (callable)

**Files:** `test/domain/usecases/save_translation_test.dart`, `lib/domain/usecases/save_translation.dart`

- [ ] 1. **Write the failing test** — `test/domain/usecases/save_translation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/domain/usecases/save_translation.dart';

import '../../fakes/fake_history_repository.dart';

TranslationResult _sample() => TranslationResult(
      sourceText: '안녕',
      translatedText: 'やあ',
      direction: LanguageDirection.koToJa(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );

void main() {
  late FakeHistoryRepository repo;
  late SaveTranslation save;

  setUp(() {
    repo = FakeHistoryRepository();
    save = SaveTranslation(repo);
  });

  test('delegates to repository.save and returns Ok(id)', () async {
    final result = await save(_sample());
    expect(result, isA<Ok<int>>());
    expect(repo.savedArgs, hasLength(1));
    expect(repo.savedArgs.single.translatedText, 'やあ');
  });

  test('propagates Err on failure', () async {
    repo.failSave = const StorageFailure('boom');
    final result = await save(_sample());
    expect(result, isA<Err<int>>());
    expect((result as Err<int>).failure, isA<StorageFailure>());
  });
}
```

- [ ] 2. **Run to fail**: `flutter test test/domain/usecases/save_translation_test.dart`
  - 기대: `'SaveTranslation' isn't defined`.
- [ ] 3. **Minimal implementation** — `lib/domain/usecases/save_translation.dart`:

```dart
import '../../core/result.dart';
import '../entities/translation_result.dart';
import '../../data/repositories/history_repository.dart';

/// Persists a translation result. Callable: `await saveTranslation(result)`.
class SaveTranslation {
  final HistoryRepository _repository;
  const SaveTranslation(this._repository);

  Future<Result<int>> call(TranslationResult result) {
    return _repository.save(result);
  }
}
```

- [ ] 4. **Run to pass**: `flutter test test/domain/usecases/save_translation_test.dart`
  - 기대: `All tests passed!`.
- [ ] 5. Commit: `feat: SaveTranslation usecase`

---

## Task 6 — UseCase: GetHistory (callable)

**Files:** `test/domain/usecases/get_history_test.dart`, `lib/domain/usecases/get_history.dart`

- [ ] 1. **Write the failing test** — `test/domain/usecases/get_history_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/domain/usecases/get_history.dart';

import '../../fakes/fake_history_repository.dart';

TranslationResult _sample({required int at}) => TranslationResult(
      sourceText: 's$at',
      translatedText: 't$at',
      direction: LanguageDirection.koToJa(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(at),
    );

void main() {
  late FakeHistoryRepository repo;
  late GetHistory getHistory;

  setUp(() {
    repo = FakeHistoryRepository();
    getHistory = GetHistory(repo);
  });

  test('returns Ok(list) newest-first', () async {
    await repo.save(_sample(at: 1000));
    await repo.save(_sample(at: 3000));
    await repo.save(_sample(at: 2000));

    final result = await getHistory();
    expect(result, isA<Ok<List<TranslationResult>>>());
    final list = (result as Ok<List<TranslationResult>>).value;
    expect(list.map((e) => e.createdAt.millisecondsSinceEpoch).toList(),
        [3000, 2000, 1000]);
  });

  test('propagates Err on failure', () async {
    repo.failGetAll = const StorageFailure('boom');
    final result = await getHistory();
    expect((result as Err<List<TranslationResult>>).failure, isA<StorageFailure>());
  });
}
```

- [ ] 2. **Run to fail**: `flutter test test/domain/usecases/get_history_test.dart`
  - 기대: `'GetHistory' isn't defined`.
- [ ] 3. **Minimal implementation** — `lib/domain/usecases/get_history.dart`:

```dart
import '../../core/result.dart';
import '../entities/translation_result.dart';
import '../../data/repositories/history_repository.dart';

/// Loads all history entries, newest first. Callable: `await getHistory()`.
class GetHistory {
  final HistoryRepository _repository;
  const GetHistory(this._repository);

  Future<Result<List<TranslationResult>>> call() {
    return _repository.getAll();
  }
}
```

- [ ] 4. **Run to pass**: `flutter test test/domain/usecases/get_history_test.dart`
  - 기대: `All tests passed!`.
- [ ] 5. Commit: `feat: GetHistory usecase`

---

## Task 7 — UseCase: DeleteHistoryEntry (callable)

**Files:** `test/domain/usecases/delete_history_entry_test.dart`, `lib/domain/usecases/delete_history_entry.dart`

- [ ] 1. **Write the failing test** — `test/domain/usecases/delete_history_entry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/domain/usecases/delete_history_entry.dart';

import '../../fakes/fake_history_repository.dart';

void main() {
  late FakeHistoryRepository repo;
  late DeleteHistoryEntry deleteEntry;

  setUp(() {
    repo = FakeHistoryRepository();
    deleteEntry = DeleteHistoryEntry(repo);
  });

  test('delegates to repository.delete with the id', () async {
    final result = await deleteEntry(42);
    expect(result, isA<Ok<void>>());
    expect(repo.deletedIds, [42]);
  });

  test('propagates Err on failure', () async {
    repo.failDelete = const StorageFailure('boom');
    final result = await deleteEntry(1);
    expect((result as Err<void>).failure, isA<StorageFailure>());
  });
}
```

- [ ] 2. **Run to fail**: `flutter test test/domain/usecases/delete_history_entry_test.dart`
  - 기대: `'DeleteHistoryEntry' isn't defined`.
- [ ] 3. **Minimal implementation** — `lib/domain/usecases/delete_history_entry.dart`:

```dart
import '../../core/result.dart';
import '../../data/repositories/history_repository.dart';

/// Deletes a single history entry by id. Callable: `await deleteEntry(id)`.
class DeleteHistoryEntry {
  final HistoryRepository _repository;
  const DeleteHistoryEntry(this._repository);

  Future<Result<void>> call(int id) {
    return _repository.delete(id);
  }
}
```

- [ ] 4. **Run to pass**: `flutter test test/domain/usecases/delete_history_entry_test.dart`
  - 기대: `All tests passed!`.
- [ ] 5. Commit: `feat: DeleteHistoryEntry usecase`

---

## Task 8 — UseCase: ClearHistory (callable)

**Files:** `test/domain/usecases/clear_history_test.dart`, `lib/domain/usecases/clear_history.dart`

- [ ] 1. **Write the failing test** — `test/domain/usecases/clear_history_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/domain/usecases/clear_history.dart';

import '../../fakes/fake_history_repository.dart';

void main() {
  late FakeHistoryRepository repo;
  late ClearHistory clearHistory;

  setUp(() {
    repo = FakeHistoryRepository();
    clearHistory = ClearHistory(repo);
  });

  test('delegates to repository.clear', () async {
    final result = await clearHistory();
    expect(result, isA<Ok<void>>());
    expect(repo.clearCount, 1);
  });

  test('propagates Err on failure', () async {
    repo.failClear = const StorageFailure('boom');
    final result = await clearHistory();
    expect((result as Err<void>).failure, isA<StorageFailure>());
  });
}
```

- [ ] 2. **Run to fail**: `flutter test test/domain/usecases/clear_history_test.dart`
  - 기대: `'ClearHistory' isn't defined`.
- [ ] 3. **Minimal implementation** — `lib/domain/usecases/clear_history.dart`:

```dart
import '../../core/result.dart';
import '../../data/repositories/history_repository.dart';

/// Deletes every history entry. Callable: `await clearHistory()`.
class ClearHistory {
  final HistoryRepository _repository;
  const ClearHistory(this._repository);

  Future<Result<void>> call() {
    return _repository.clear();
  }
}
```

- [ ] 4. **Run to pass**: `flutter test test/domain/usecases/clear_history_test.dart`
  - 기대: `All tests passed!`.
- [ ] 5. Commit: `feat: ClearHistory usecase`

---

## Task 9 — HistoryController: 반응형 로드 + 에러 상태

**Files:** `test/presentation/history/history_controller_test.dart`, `lib/presentation/history/history_controller.dart`

> 컨트롤러는 GetxController. 상태: `entries` (RxList), `isLoading` (RxBool), `errorMessage` (RxnString). `Result`는 Dart 3 sealed `switch`로 처리한다. 위젯 없이 순수 로직 테스트.

- [ ] 1. **Write the failing test** — `test/presentation/history/history_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:translate_ko_jp/core/failure.dart';
import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/domain/usecases/get_history.dart';
import 'package:translate_ko_jp/domain/usecases/delete_history_entry.dart';
import 'package:translate_ko_jp/domain/usecases/clear_history.dart';
import 'package:translate_ko_jp/presentation/history/history_controller.dart';

import '../../fakes/fake_history_repository.dart';
import '../../fakes/fake_tts_service.dart';

TranslationResult _entry({required int at, String src = '안녕', String tr = 'やあ'}) =>
    TranslationResult(
      sourceText: src,
      translatedText: tr,
      direction: LanguageDirection.koToJa(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(at),
    );

HistoryController _build(FakeHistoryRepository repo, FakeTtsService tts) {
  return HistoryController(
    getHistory: GetHistory(repo),
    deleteHistoryEntry: DeleteHistoryEntry(repo),
    clearHistory: ClearHistory(repo),
    tts: tts,
  );
}

void main() {
  late FakeHistoryRepository repo;
  late FakeTtsService tts;

  setUp(() {
    repo = FakeHistoryRepository();
    tts = FakeTtsService();
  });

  test('load populates entries newest-first and clears loading/error', () async {
    await repo.save(_entry(at: 1000));
    await repo.save(_entry(at: 3000));
    await repo.save(_entry(at: 2000));

    final c = _build(repo, tts);
    await c.load();

    expect(c.isLoading.value, isFalse);
    expect(c.errorMessage.value, isNull);
    expect(c.entries.map((e) => e.createdAt.millisecondsSinceEpoch).toList(),
        [3000, 2000, 1000]);
  });

  test('load sets errorMessage on failure', () async {
    repo.failGetAll = const StorageFailure('db down');
    final c = _build(repo, tts);
    await c.load();

    expect(c.entries, isEmpty);
    expect(c.errorMessage.value, 'db down');
    expect(c.isLoading.value, isFalse);
  });

  test('deleteEntry removes the row and reloads', () async {
    await repo.save(_entry(at: 1000, src: 'keep'));
    final r = await repo.save(_entry(at: 2000, src: 'drop'));
    final dropId = (r as dynamic).value as int;

    final c = _build(repo, tts);
    await c.load();
    expect(c.entries, hasLength(2));

    await c.deleteEntry(dropId);

    expect(repo.deletedIds, contains(dropId));
    expect(c.entries.map((e) => e.sourceText), ['keep']);
  });

  test('clearAll empties the list', () async {
    await repo.save(_entry(at: 1000));
    await repo.save(_entry(at: 2000));

    final c = _build(repo, tts);
    await c.load();
    await c.clearAll();

    expect(repo.clearCount, 1);
    expect(c.entries, isEmpty);
  });

  test('play speaks translatedText in the target language', () async {
    final entry = _entry(at: 1000); // ko->ja, target = ja
    final c = _build(repo, tts);

    await c.play(entry);

    expect(tts.spoken, hasLength(1));
    expect(tts.spoken.single.text, 'やあ');
    expect(tts.spoken.single.language.name, 'ja');
  });

  test('deleteEntry surfaces failure as errorMessage', () async {
    final r = await repo.save(_entry(at: 1000));
    final id = (r as dynamic).value as int;
    final c = _build(repo, tts);
    await c.load();

    repo.failDelete = const StorageFailure('del fail');
    await c.deleteEntry(id);

    expect(c.errorMessage.value, 'del fail');
  });
}
```

- [ ] 2. **Run to fail**: `flutter test test/presentation/history/history_controller_test.dart`
  - 기대: `'HistoryController' isn't defined`.
- [ ] 3. **Minimal implementation** — `lib/presentation/history/history_controller.dart`:

```dart
import 'package:get/get.dart';

import '../../core/result.dart';
import '../../domain/entities/translation_result.dart';
import '../../domain/usecases/get_history.dart';
import '../../domain/usecases/delete_history_entry.dart';
import '../../domain/usecases/clear_history.dart';
import '../../data/services/tts_service.dart';

class HistoryController extends GetxController {
  final GetHistory _getHistory;
  final DeleteHistoryEntry _deleteHistoryEntry;
  final ClearHistory _clearHistory;
  final TtsService _tts;

  HistoryController({
    required GetHistory getHistory,
    required DeleteHistoryEntry deleteHistoryEntry,
    required ClearHistory clearHistory,
    required TtsService tts,
  })  : _getHistory = getHistory,
        _deleteHistoryEntry = deleteHistoryEntry,
        _clearHistory = clearHistory,
        _tts = tts;

  final RxList<TranslationResult> entries = <TranslationResult>[].obs;
  final RxBool isLoading = false.obs;
  final RxnString errorMessage = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = null;
    final result = await _getHistory();
    switch (result) {
      case Ok<List<TranslationResult>>(value: final list):
        entries.assignAll(list);
      case Err<List<TranslationResult>>(failure: final f):
        errorMessage.value = f.message;
    }
    isLoading.value = false;
  }

  Future<void> deleteEntry(int id) async {
    final result = await _deleteHistoryEntry(id);
    switch (result) {
      case Ok<void>():
        entries.removeWhere((e) => e.id == id);
      case Err<void>(failure: final f):
        errorMessage.value = f.message;
    }
  }

  Future<void> clearAll() async {
    final result = await _clearHistory();
    switch (result) {
      case Ok<void>():
        entries.clear();
      case Err<void>(failure: final f):
        errorMessage.value = f.message;
    }
  }

  /// Replays a history item's translated text using the target language voice.
  Future<void> play(TranslationResult entry) async {
    await _tts.stop();
    await _tts.speak(
      text: entry.translatedText,
      language: entry.direction.to,
    );
  }
}
```

- [ ] 4. **Run to pass**: `flutter test test/presentation/history/history_controller_test.dart`
  - 기대: `All tests passed!`.
- [ ] 5. Commit: `feat: HistoryController with reactive load, delete, clear, TTS replay`

---

## Task 10 — HistoryScreen 위젯 스모크 테스트 + 구현

**Files:** `test/presentation/history/history_screen_test.dart`, `lib/presentation/history/history_screen.dart`

> 화면은 최신순 목록. 각 아이템: source + translated + 방향(`from.nativeLabel → to.nativeLabel`) + 타임스탬프, 그리고 복사 / 재생(TTS) / 삭제 버튼. 앱바에 전체삭제(확인 다이얼로그). 복사는 `Clipboard.setData`. 위젯 테스트는 `Get.put`으로 컨트롤러 주입.

- [ ] 1. **Write the failing test** — `test/presentation/history/history_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/domain/usecases/get_history.dart';
import 'package:translate_ko_jp/domain/usecases/delete_history_entry.dart';
import 'package:translate_ko_jp/domain/usecases/clear_history.dart';
import 'package:translate_ko_jp/presentation/history/history_controller.dart';
import 'package:translate_ko_jp/presentation/history/history_screen.dart';

import '../../fakes/fake_history_repository.dart';
import '../../fakes/fake_tts_service.dart';

TranslationResult _entry({required int at, String src = '안녕', String tr = 'やあ'}) =>
    TranslationResult(
      sourceText: src,
      translatedText: tr,
      direction: LanguageDirection.koToJa(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(at),
    );

void main() {
  late FakeHistoryRepository repo;
  late FakeTtsService tts;

  setUp(() {
    repo = FakeHistoryRepository();
    tts = FakeTtsService();
  });

  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester) async {
    Get.put<HistoryController>(HistoryController(
      getHistory: GetHistory(repo),
      deleteHistoryEntry: DeleteHistoryEntry(repo),
      clearHistory: ClearHistory(repo),
      tts: tts,
    ));
    await tester.pumpWidget(const GetMaterialApp(home: HistoryScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('renders entries newest-first with source and translated text',
      (tester) async {
    await repo.save(_entry(at: 1000, src: 'old', tr: 'ふるい'));
    await repo.save(_entry(at: 2000, src: 'new', tr: 'あたらしい'));

    await pump(tester);

    expect(find.text('old'), findsOneWidget);
    expect(find.text('あたらしい'), findsOneWidget);

    // newest ('new') should appear above oldest ('old').
    final newY = tester.getTopLeft(find.text('new')).dy;
    final oldY = tester.getTopLeft(find.text('old')).dy;
    expect(newY, lessThan(oldY));
  });

  testWidgets('shows empty state when there is no history', (tester) async {
    await pump(tester);
    expect(find.text('히스토리가 없습니다'), findsOneWidget);
  });

  testWidgets('tapping play speaks the translated text', (tester) async {
    await repo.save(_entry(at: 1000, tr: 'やあ'));
    await pump(tester);

    await tester.tap(find.byIcon(Icons.volume_up).first);
    await tester.pump();

    expect(tts.spoken.single.text, 'やあ');
  });

  testWidgets('tapping delete removes the item', (tester) async {
    await repo.save(_entry(at: 1000, src: 'doomed'));
    await pump(tester);
    expect(find.text('doomed'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();

    expect(find.text('doomed'), findsNothing);
  });

  testWidgets('clear-all confirm dialog empties the list', (tester) async {
    await repo.save(_entry(at: 1000, src: 'a'));
    await repo.save(_entry(at: 2000, src: 'b'));
    await pump(tester);

    await tester.tap(find.byIcon(Icons.delete_sweep));
    await tester.pumpAndSettle();

    // Confirm dialog visible.
    expect(find.text('전체 삭제'), findsWidgets);
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(find.text('a'), findsNothing);
    expect(find.text('b'), findsNothing);
    expect(repo.clearCount, 1);
  });
}
```

- [ ] 2. **Run to fail**: `flutter test test/presentation/history/history_screen_test.dart`
  - 기대: `'HistoryScreen' isn't defined`.
- [ ] 3. **Minimal implementation** — `lib/presentation/history/history_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../domain/entities/translation_result.dart';
import 'history_controller.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<HistoryController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('번역 히스토리'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: '전체 삭제',
            onPressed: () => _confirmClearAll(context, controller),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        final error = controller.errorMessage.value;
        if (error != null && controller.entries.isEmpty) {
          return Center(child: Text(error));
        }
        if (controller.entries.isEmpty) {
          return const Center(child: Text('히스토리가 없습니다'));
        }
        return ListView.separated(
          itemCount: controller.entries.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final entry = controller.entries[index];
            return _HistoryTile(entry: entry, controller: controller);
          },
        );
      }),
    );
  }

  Future<void> _confirmClearAll(
    BuildContext context,
    HistoryController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('전체 삭제'),
        content: const Text('모든 번역 히스토리를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.clearAll();
    }
  }
}

class _HistoryTile extends StatelessWidget {
  final TranslationResult entry;
  final HistoryController controller;

  const _HistoryTile({required this.entry, required this.controller});

  String get _directionLabel =>
      '${entry.direction.from.nativeLabel} → ${entry.direction.to.nativeLabel}';

  String get _timestamp {
    final d = entry.createdAt;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _directionLabel,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              Text(
                _timestamp,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(entry.sourceText),
          const SizedBox(height: 2),
          Text(
            entry.translatedText,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: '복사',
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: entry.translatedText),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.volume_up),
                tooltip: '재생',
                onPressed: () => controller.play(entry),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '삭제',
                onPressed: () {
                  final id = entry.id;
                  if (id != null) controller.deleteEntry(id);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] 4. **Run to pass**: `flutter test test/presentation/history/history_screen_test.dart`
  - 기대: `All tests passed!`. (만약 `delete_sweep`/아이콘 finder 충돌 시 finder를 구체화하고 화면 위젯을 맞춘다.)
- [ ] 5. Commit: `feat: HistoryScreen with list, copy/play/delete, clear-all dialog`

---

## Task 11 — DI: registerHistoryDeps()

**Files:** `test/app/history_deps_test.dart`, `lib/app/history_deps.dart`

> `app/bindings.dart`/`routes.dart`는 수정하지 않는다. 히스토리 의존만 등록하는 함수를 별도 파일에 노출한다. store는 file 경로로 열어야 하므로(`getDatabasesPath` + `join`), 등록은 **store open을 await**하는 비동기 초기화가 필요하다. GetX 패턴상 `Get.putAsync` 사용.

- [ ] 1. **Write the failing test** — `test/app/history_deps_test.dart` (FFI로 실제 file open 경로까지 검증):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:translate_ko_jp/data/services/tts_service.dart';
import 'package:translate_ko_jp/data/services/history_store.dart';
import 'package:translate_ko_jp/data/repositories/history_repository.dart';
import 'package:translate_ko_jp/domain/usecases/save_translation.dart';
import 'package:translate_ko_jp/domain/usecases/get_history.dart';
import 'package:translate_ko_jp/domain/usecases/delete_history_entry.dart';
import 'package:translate_ko_jp/domain/usecases/clear_history.dart';
import 'package:translate_ko_jp/presentation/history/history_controller.dart';
import 'package:translate_ko_jp/app/history_deps.dart';

import '../fakes/fake_tts_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    // TtsService is owned by plan 01; provide a Fake so history deps resolve.
    Get.put<TtsService>(FakeTtsService());
  });

  tearDown(Get.reset);

  test('registerHistoryDeps wires store, repo, usecases, controller', () async {
    await registerHistoryDeps(databasePath: inMemoryDatabasePath);

    expect(Get.isRegistered<HistoryStore>(), isTrue);
    expect(Get.isRegistered<HistoryRepository>(), isTrue);
    expect(Get.isRegistered<SaveTranslation>(), isTrue);
    expect(Get.isRegistered<GetHistory>(), isTrue);
    expect(Get.isRegistered<DeleteHistoryEntry>(), isTrue);
    expect(Get.isRegistered<ClearHistory>(), isTrue);

    // Controller resolvable and functional end-to-end (insert via usecase).
    final save = Get.find<SaveTranslation>();
    final controller = Get.find<HistoryController>();
    expect(save, isA<SaveTranslation>());
    expect(controller, isA<HistoryController>());
  });
}
```

- [ ] 2. **Run to fail**: `flutter test test/app/history_deps_test.dart`
  - 기대: `'registerHistoryDeps' isn't defined` / `Target of URI doesn't exist`.
- [ ] 3. **Minimal implementation** — `lib/app/history_deps.dart`:

```dart
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../data/services/history_store.dart';
import '../data/services/sqflite_history_store.dart';
import '../data/services/tts_service.dart';
import '../data/repositories/history_repository.dart';
import '../domain/usecases/save_translation.dart';
import '../domain/usecases/get_history.dart';
import '../domain/usecases/delete_history_entry.dart';
import '../domain/usecases/clear_history.dart';
import '../presentation/history/history_controller.dart';

/// Registers all history-flow dependencies with GetX.
///
/// Does NOT touch [app/bindings.dart] or [app/routes.dart] (foundation owns
/// them). The integration plan (05) calls this from AppBinding.
///
/// [databasePath] is injectable for tests (pass `inMemoryDatabasePath`).
/// When null, the on-device app documents DB path is used.
/// Assumes a [TtsService] is already registered (owned by plan 01); in tests
/// a Fake is put first.
Future<void> registerHistoryDeps({String? databasePath}) async {
  final path = databasePath ??
      p.join(await getDatabasesPath(), 'translate_ko_jp.db');

  final store = SqfliteHistoryStore();
  await store.open(path: path);
  Get.put<HistoryStore>(store, permanent: true);

  Get.put<HistoryRepository>(
    HistoryRepositoryImpl(Get.find<HistoryStore>()),
    permanent: true,
  );

  Get.put<SaveTranslation>(
    SaveTranslation(Get.find<HistoryRepository>()),
    permanent: true,
  );
  Get.put<GetHistory>(
    GetHistory(Get.find<HistoryRepository>()),
    permanent: true,
  );
  Get.put<DeleteHistoryEntry>(
    DeleteHistoryEntry(Get.find<HistoryRepository>()),
    permanent: true,
  );
  Get.put<ClearHistory>(
    ClearHistory(Get.find<HistoryRepository>()),
    permanent: true,
  );

  Get.lazyPut<HistoryController>(
    () => HistoryController(
      getHistory: Get.find<GetHistory>(),
      deleteHistoryEntry: Get.find<DeleteHistoryEntry>(),
      clearHistory: Get.find<ClearHistory>(),
      tts: Get.find<TtsService>(),
    ),
  );
}
```

- [ ] 4. **Run to pass**: `flutter test test/app/history_deps_test.dart`
  - 기대: `All tests passed!`.
- [ ] 5. Commit: `feat: registerHistoryDeps for history flow DI`

---

## Task 12 — SaveTranslation 시드(seam) 연결 문서화

**Files:** (없음 — 문서/검증만. plan 01 파일 수정 금지)

> 번역 완료 시 `SaveTranslation`을 호출하는 실제 와이어링은 **plan 05(통합)** 의 책임이다. plan 01은 `onTranslated`/`lastResult` seam을 노출한다(가정). 이 태스크는 그 연결을 **편집 없이** 가능한지 확인하고 기록만 한다.

- [ ] 1. plan 01의 산출물(`lib/presentation/translation/translation_controller.dart`)이 외부에서 구독 가능한 seam(`onTranslated` 콜백 또는 `Rx<TranslationResult?> lastResult`)을 노출하는지 확인한다.
- [ ] 2. **편집 없이 연결 가능하면**: `registerHistoryDeps()` 또는 05 통합 지점에서 다음 패턴을 적용하도록 메모를 남긴다 (이 플랜에서는 코드 추가 안 함 — 컨트롤러가 plan 01 소유이므로):

```dart
// (plan 05에서 적용) translation 완료 → 히스토리 자동 저장 예시
// final translation = Get.find<TranslationController>();
// final save = Get.find<SaveTranslation>();
// ever(translation.lastResult, (TranslationResult? r) {
//   if (r != null) save(r); // StorageFailure는 비치명적: 로그/토스트만
// });
```

- [ ] 3. **편집이 필요하면**(seam이 없으면): plan 05로 명시적으로 넘긴다. 이 플랜에서는 plan 01 파일을 수정하지 않는다. 결정 사항을 커밋 메시지에 남긴다.
- [ ] 4. Commit (문서 변경이 없으면 빈 커밋 대신 생략 가능): `docs: note SaveTranslation seam wiring is deferred to integration plan 05`

---

## Task 13 — 전체 회귀 + analyze

**Files:** (없음)

- [ ] 1. Run: `flutter analyze`
  - 기대: `No issues found!` (히스토리 범위 파일에 대해 경고/에러 없음).
- [ ] 2. Run: `flutter test`
  - 기대: 모든 히스토리 테스트 통과 (`All tests passed!`). plan 00 기반이 이미 머지된 상태에서 실행.
- [ ] 3. Commit (필요 시): `test: full history-flow regression green`

---

## 완료 기준 (Definition of Done)

- [ ] `pubspec.yaml`에 `sqflite`, `path`(deps), `sqflite_common_ffi`(dev_deps) 추가됨.
- [ ] `lib/data/services/sqflite_history_store.dart` — `HistoryStore` 구현. `translations` 테이블(`id`/`source_text`/`translated_text`/`source_lang`/`target_lang`/`created_at`), `source_lang`/`target_lang`은 `Language.name`, `created_at`은 `millisecondsSinceEpoch`. `getAll()`은 `ORDER BY created_at DESC`.
- [ ] store 테스트가 `sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi` + `inMemoryDatabasePath`로 실제 insert/getAll/delete/clear 라운드트립을 검증.
- [ ] `lib/data/repositories/history_repository.dart` — `HistoryRepositoryImpl`이 store를 감싸 `Result<...>` 반환, 예외를 `StorageFailure`로 매핑. 시그니처가 INDEX와 정확히 일치.
- [ ] UseCase 4종 (`SaveTranslation`, `GetHistory`, `DeleteHistoryEntry`, `ClearHistory`) — callable(`call`) 클래스, 각각 단위 테스트.
- [ ] `lib/presentation/history/history_controller.dart` — 반응형 로드(newest-first), delete-one, clear-all, copy(화면), TTS 재생(`TtsService` 인터페이스 의존, Fake로 테스트), `Result`는 Dart 3 sealed `switch`로 처리.
- [ ] `lib/presentation/history/history_screen.dart` — 최신순 목록, 항목별 source/translated/방향/타임스탬프 + 복사/재생/삭제, 앱바 전체삭제(확인 다이얼로그). 위젯 스모크 테스트 통과.
- [ ] `lib/app/history_deps.dart`의 `registerHistoryDeps()`가 store→repo→usecase→controller를 등록. `app/bindings.dart`·`app/routes.dart` 미수정.
- [ ] `test/fakes/`에 `FakeHistoryStore`, `FakeHistoryRepository`, `FakeTtsService` 존재.
- [ ] `TtsServiceImpl`/네이티브 코드/plan 01 파일은 수정·구현하지 않음. `SaveTranslation` 실제 seam 연결은 plan 05로 명시적으로 위임됨.
- [ ] `flutter analyze` 무경고, `flutter test` 전체 통과.
