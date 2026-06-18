# 통합 & 마무리 (Integration) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 병렬로 완성된 번역/모델/히스토리/iOS 플로우를 하나의 앱으로 연결하고(라우팅·DI·히스토리 시임), 기존 MVP 코드를 제거한 뒤 전체 테스트·분석을 통과시킨다.

**Architecture:** `AppBinding`이 각 플로우의 `register*Deps()`를 호출하고, 앱 부트스트랩이 모델 상태에 따라 초기 라우트를 정한다. 번역 완료 시 `TranslationController.onTranslated` 시임을 `SaveTranslation`에 연결해 히스토리에 자동 저장한다.

**Tech Stack:** Flutter, Dart 3, GetX, flutter_test

> 선행: `01`, `02`, `03` 완료(머지). `04`는 iOS 빌드용으로 독립. 모든 시그니처는 `2026-06-18-00-INDEX.md` 계약을 따른다.

---

### Task 1: 의존성 정리 & pub get

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 최종 의존성 확인**

`pubspec.yaml`의 `dependencies`에 다음이 모두 있어야 한다(각 플로우가 추가했을 것 — 누락 시 채운다): `get`, `speech_to_text`, `flutter_tts`, `permission_handler`, `path_provider`, `http`, `file_picker`, `crypto`, `sqflite`, `path`. `dev_dependencies`에 `sqflite_common_ffi`.

- [ ] **Step 2: pub get 실행**

Run: `flutter pub get`
Expected: `Got dependencies!` (버전 충돌 없음)

- [ ] **Step 3: 커밋**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: consolidate dependencies across flows"
```

---

### Task 2: 전역 DI 부트스트랩

**Files:**
- Modify: `lib/app/bindings.dart`

> 주의: `registerHistoryDeps()`(플로우 03)는 **async**(DB open)이고 `registerModelDeps()`/`registerTranslationDeps()`는 동기다. 또한 `registerHistoryDeps`는 `TtsService`가 먼저 등록돼 있다고 가정하므로(플로우 01 소유), **순서**가 중요하다: translation → model → history. `Bindings.dependencies()`는 동기라 async 등록을 담을 수 없으므로, `AppBinding` 대신 **async 부트스트랩 함수**를 노출하고 `main()`에서 `await` 한다.

- [ ] **Step 1: 부트스트랩 함수로 교체**

`lib/app/bindings.dart` (foundation의 `AppBinding` 클래스 골격을 함수로 대체):
```dart
import 'translation_deps.dart';
import 'model_deps.dart';
import 'history_deps.dart';

/// Registers all flow dependencies in dependency-safe order.
/// translation must run first (owns InferenceService/TtsService that the
/// model and history flows look up). history is async (opens the DB).
Future<void> registerAllDeps() async {
  registerTranslationDeps();
  registerModelDeps();
  await registerHistoryDeps();
}
```

- [ ] **Step 2: 정적 분석으로 검증**

Run: `flutter analyze lib/app/bindings.dart`
Expected: `No issues found!`

- [ ] **Step 3: 커밋**

```bash
git add lib/app/bindings.dart
git commit -m "feat: add async registerAllDeps bootstrap wiring all flows"
```

---

### Task 3: 히스토리 자동 저장 시임 연결

**Files:**
- Modify: `lib/app/translation_deps.dart`
- Test: `test/integration/history_seam_test.dart`

> `TranslationController.onTranslated`(플로우 01) → `SaveTranslation`(플로우 03) 연결.

- [ ] **Step 1: 실패 테스트 작성**

`test/integration/history_seam_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/data/repositories/translation_repository.dart';
import 'package:translate_ko_jp/domain/usecases/listen_speech.dart';
import 'package:translate_ko_jp/domain/usecases/save_translation.dart';
import 'package:translate_ko_jp/domain/usecases/speak_text.dart';
import 'package:translate_ko_jp/domain/usecases/translate_text.dart';
import 'package:translate_ko_jp/presentation/translation/translation_controller.dart';
import '../fakes/fake_inference_service.dart';
import '../fakes/fake_speech_service.dart';
import '../fakes/fake_tts_service.dart';
import '../fakes/fake_history_repository.dart';

void main() {
  test('translation is saved to history via the seam', () async {
    final history = FakeHistoryRepository();
    final repo = TranslationRepositoryImpl(FakeInferenceService(response: 'こんにちは'));
    final controller = TranslationController(
      translateText: TranslateText(repo),
      listenSpeech: ListenSpeech(FakeSpeechService()),
      speakText: SpeakText(FakeTtsService()),
    );
    final save = SaveTranslation(history);
    controller.onTranslated = (r) => save(r);

    controller.sourceText.value = '안녕';
    await controller.translate();
    await Future<void>.delayed(Duration.zero);

    expect(history.savedArgs, hasLength(1));
    expect(history.savedArgs.single.translatedText, 'こんにちは');
  });
}
```

> `FakeHistoryRepository`는 플로우 03이 `test/fakes/fake_history_repository.dart`에 만든다(필드명 `savedArgs`). 없다면 03의 정의를 따라 동일 시그니처로 생성한다.

- [ ] **Step 2: 실행하여 실패 확인**

Run: `flutter test test/integration/history_seam_test.dart`
Expected: FAIL (시임 미연결 또는 컴파일 에러는 없지만 단언 실패 가능 — 시임은 컨트롤러 기능이므로 PASS일 수 있음). 이 테스트는 시임 계약을 고정하기 위한 회귀 테스트다.

- [ ] **Step 3: DI에서 시임 연결**

`lib/app/translation_deps.dart`의 `TranslationController` 등록을 다음과 같이 수정(히스토리 저장 연결 추가):
```dart
  Get.lazyPut<TranslationController>(
    () {
      final controller = TranslationController(
        translateText: TranslateText(Get.find<TranslationRepository>()),
        listenSpeech: ListenSpeech(Get.find<SpeechService>()),
        speakText: SpeakText(Get.find<TtsService>()),
      );
      final save = Get.find<SaveTranslation>();
      controller.onTranslated = (r) => save(r);
      return controller;
    },
    fenix: true,
  );
```
그리고 import 추가: `import '../domain/usecases/save_translation.dart';`

> `SaveTranslation`은 플로우 03의 `registerHistoryDeps()`가 `Get.lazyPut`으로 등록한다. AppBinding이 translation→history 순으로 호출해도 `lazyPut`은 지연 생성이라 순서 무관.

- [ ] **Step 4: 실행하여 통과 확인**

Run: `flutter test test/integration/history_seam_test.dart`
Expected: PASS (1 test)

- [ ] **Step 5: 커밋**

```bash
git add lib/app/translation_deps.dart test/integration/history_seam_test.dart
git commit -m "feat: auto-save translations to history via controller seam"
```

---

### Task 4: 앱 진입점 & 라우팅 (app.dart, main.dart)

**Files:**
- Create: `lib/app/app.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: GetMaterialApp 작성**

`lib/app/app.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../presentation/setup/setup_screen.dart';
import '../presentation/translation/translation_screen.dart';
import '../presentation/history/history_screen.dart';
import 'routes.dart';

class TranslateApp extends StatelessWidget {
  final String initialRoute;
  const TranslateApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: '한일 통역기',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      initialRoute: initialRoute,
      getPages: [
        GetPage(name: Routes.setup, page: () => const SetupScreen()),
        GetPage(name: Routes.translation, page: () => const TranslationScreen()),
        GetPage(name: Routes.history, page: () => const HistoryScreen()),
      ],
    );
  }
}
```

- [ ] **Step 2: main.dart 재작성**

`lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'app/app.dart';
import 'app/bindings.dart';
import 'app/routes.dart';
import 'data/repositories/model_repository.dart';
import 'domain/entities/model_status.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await registerAllDeps();

  final modelRepo = Get.find<ModelRepository>();
  final status = await modelRepo.currentStatus();
  final ready = status == ModelStatus.loaded || status == ModelStatus.downloaded;

  runApp(TranslateApp(
    initialRoute: ready ? Routes.translation : Routes.setup,
  ));
}
```

- [ ] **Step 3: 정적 분석으로 검증**

Run: `flutter analyze lib/app/app.dart lib/main.dart`
Expected: `No issues found!`

- [ ] **Step 4: 커밋**

```bash
git add lib/app/app.dart lib/main.dart
git commit -m "feat: wire app entry point, routing, and initial-route logic"
```

---

### Task 5: 기존 MVP 코드 제거

**Files:**
- Delete: `lib/controllers/translation_controller.dart`
- Delete: `lib/controllers/model_setup_controller.dart`
- Delete: `lib/services/gemma_service.dart`
- Delete: `lib/views/translation_screen.dart`
- Delete: `lib/views/model_setup_screen.dart`

- [ ] **Step 1: 잔존 참조 확인**

Run: `grep -rn "controllers/\|services/gemma_service\|views/" lib/`
Expected: 출력 없음 (신규 코드는 `presentation/`, `data/`만 참조). 출력이 있으면 해당 import를 신규 경로로 교체.

- [ ] **Step 2: 구 파일 삭제**

```bash
git rm lib/controllers/translation_controller.dart \
       lib/controllers/model_setup_controller.dart \
       lib/services/gemma_service.dart \
       lib/views/translation_screen.dart \
       lib/views/model_setup_screen.dart
```

- [ ] **Step 3: 전체 분석**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: 커밋**

```bash
git commit -m "refactor: remove legacy MVP controllers, services, and views"
```

---

### Task 6: 전체 테스트 & 스모크 확인

**Files:**
- Modify: `test/widget_test.dart` (기본 카운터 테스트 제거/교체)

- [ ] **Step 1: 기본 위젯 테스트 교체**

`test/widget_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:translate_ko_jp/app/app.dart';
import 'package:translate_ko_jp/app/routes.dart';
import 'package:translate_ko_jp/app/translation_deps.dart';
import 'package:translate_ko_jp/app/model_deps.dart';

void main() {
  // Setup route needs only the (sync) translation + model deps; history opens
  // a DB asynchronously and is exercised in its own flow tests instead.
  testWidgets('app boots to setup route without crashing', (tester) async {
    registerTranslationDeps();
    registerModelDeps();

    await tester.pumpWidget(const TranslateApp(initialRoute: Routes.setup));
    await tester.pump();

    expect(find.byType(TranslateApp), findsOneWidget);
    Get.reset();
  });
}
```

- [ ] **Step 2: 전체 테스트 실행**

Run: `flutter test`
Expected: 모든 테스트 PASS (00~05 누적)

- [ ] **Step 3: 전체 분석**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: 커밋**

```bash
git add test/widget_test.dart
git commit -m "test: replace default widget test with app boot smoke test"
```

---

### Task 7: (선택, Mac 필요) 디바이스 E2E 수동 검증

- [ ] **Step 1:** Android 기기에서 `flutter run`, 설정 화면에서 모델 다운로드 → 로드 → 한국어 발화 → 일본어 번역/TTS 확인.
- [ ] **Step 2:** (Mac 필요) iOS 기기에서 동일 시나리오 확인 (플로우 04 완료 전제).
- [ ] **Step 3:** 히스토리 화면에서 저장/삭제/복사/재생 확인.

> 이 태스크는 실기기 수동 검증이라 자동 PASS가 없다. 결과를 PR 설명에 기록한다.

---

## 완료 기준

- [ ] `flutter test` 전체 PASS
- [ ] `flutter analyze` 이슈 없음
- [ ] 앱이 모델 상태에 따라 setup/translation으로 분기 진입
- [ ] 번역 완료 시 히스토리에 자동 저장됨 (시임 테스트 통과)
- [ ] 구 MVP 코드(`controllers/`, `services/gemma_service.dart`, `views/`) 제거됨
- [ ] (Mac) iOS 빌드 및 실기기 통역 동작 확인
