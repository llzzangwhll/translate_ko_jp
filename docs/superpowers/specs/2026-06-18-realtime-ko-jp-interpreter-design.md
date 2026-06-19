# 한↔일 온디바이스 실시간 통역 앱 — 설계 스펙

- **작성일**: 2026-06-18
- **상태**: 설계 확정 (구현 계획 작성 전)
- **대상**: 기존 MVP(`translate_ko_jp`) 리팩터링 + 기능 확장

---

## 1. 목적 / 배경

사용자가 한국어 또는 일본어를 **음성으로 발화**하면, 온디바이스 LLM(Gemma 4)으로 **반대 언어로 번역**하여 화면에 표시하고 음성으로 읽어주는 모바일 통역 앱.

기존 코드는 첫 작업물(MVP)로, 동작은 하지만 다음 문제가 있어 개선이 필요하다:

- 비즈니스 로직(STT·TTS·번역·모델 로딩)이 `TranslationController` 한 곳에 섞여 있어 계층 분리·테스트가 어렵다.
- iOS 네이티브 추론이 구현돼 있지 않다 (MethodChannel 인터페이스만 존재).
- 에러 처리와 모델 경로 탐색이 산발적이다.
- 모델 파일 확보가 수동 파일 선택/자동 탐색뿐이라 일반 사용자 UX로는 약하다.
- 번역 결과를 보관하지 않는다.

## 2. 범위 (Scope)

### 포함

- **MVVM 계층 재구성** (GetX 유지, View → ViewModel → UseCase/Repository → Service).
- **발화 종료 후 문장 단위 번역** (STT 최종 결과 기준). *실시간 스트리밍 번역은 범위 밖.*
- **Android + iOS** 동시 지원. iOS 네이티브 추론 구현 포함.
- **인앱 모델 다운로드** (진행률/재개/취소/체크섬 검증).
- **번역 히스토리 저장** (조회/삭제/복사/TTS 재생).
- 추론 백엔드 **MediaPipe 유지**, 단 Service 인터페이스로 추상화해 향후 LiteRT-LM 교체 대비.

### 제외 (YAGNI)

- 준실시간/토큰 스트리밍 동시통역.
- 2인 대화형(양방향 동시) 전용 화면 — 방향 토글로 대체. (추후 후보)
- 클라우드 번역 폴백.
- AICore(Android 전용) 경로 — 크로스플랫폼 요건과 불일치.

## 3. 핵심 결정 사항

| 항목 | 결정 | 근거 |
|---|---|---|
| 실시간 범위 | 발화 종료 후 문장 단위 번역 | 온디바이스 1~4B 추론 현실성·안정성 |
| 상태관리/DI | **GetX 유지** + 계층 분리 | 마이그레이션 비용 최소, 분리·테스트 확보 |
| 플랫폼 | **Android + iOS** | 요구사항 |
| 추론 백엔드 | **MediaPipe** (`tasks-genai`), 인터페이스 추상화 | 이미 Android 구현 존재, 양 플랫폼 동일 API. MediaPipe LLM API는 maintenance-only → 향후 LiteRT-LM 이전 여지 확보 |
| 모델 | **Gemma 4 E2B** (`.task`) | 온디바이스용, ~1.5GB RAM, 디바이스 호환성 우선 |
| 모델 배포 | **인앱 다운로드** | 앱스토어 등록 가능, UX 깔끔 |
| 히스토리 저장 | 로컬 DB(**sqflite**), Repository로 추상화 | 표준·경량, 조회/삭제 SQL 용이, 교체 가능 |

## 4. 아키텍처

### 4.1 계층 구조

```
View (Widget)
  └─ ViewModel (GetxController)        # UI 상태(.obs), 사용자 액션 조율
        └─ UseCase                      # 단일 책임 비즈니스 동작 (테스트 1순위)
              └─ Repository             # 데이터 출처 조율
                    └─ Service (추상)   # STT / TTS / Inference / Download / History
                          └─ Platform  # MethodChannel, 플러그인, 네이티브
```

**원칙**: ViewModel은 "상태 + 조율"만. 도메인 로직은 UseCase로, 외부 의존(STT/TTS/추론/다운로드/DB)은 Service 인터페이스 뒤로 격리한다.

### 4.2 디렉터리 구조

```
lib/
├─ app/
│   ├─ main.dart
│   ├─ app.dart                 # GetMaterialApp, 테마, 라우팅
│   ├─ routes.dart
│   └─ bindings.dart            # GetX DI 바인딩 (Service/Repo/UseCase 등록)
├─ core/
│   ├─ result.dart              # Result<T> = Success<T> | Failure
│   ├─ failure.dart             # Failure 계층 (Permission/Network/Model/Inference/Storage)
│   ├─ language.dart            # Language enum (ko, ja) + locale/label/tts 코드 매핑
│   └─ constants.dart
├─ domain/
│   ├─ entities/
│   │   ├─ translation_result.dart   # source, translated, direction, createdAt
│   │   ├─ language_direction.dart    # from, to
│   │   └─ model_status.dart          # notDownloaded | downloading | ready | loaded | error
│   └─ usecases/
│       ├─ translate_text.dart
│       ├─ listen_speech.dart
│       ├─ speak_text.dart
│       ├─ ensure_model_ready.dart    # 존재확인→(다운로드)→로드
│       ├─ save_translation.dart
│       ├─ get_history.dart
│       └─ delete_history_entry.dart
├─ data/
│   ├─ services/
│   │   ├─ speech_service.dart                 # 인터페이스
│   │   ├─ speech_service_impl.dart            # speech_to_text 래핑
│   │   ├─ tts_service.dart / _impl.dart       # flutter_tts 래핑
│   │   ├─ inference_service.dart              # 인터페이스 (translate/load/isLoaded/exists)
│   │   ├─ mediapipe_inference_service.dart    # MethodChannel 구현
│   │   ├─ model_download_service.dart / _impl # http 스트리밍 + 진행률/재개/체크섬
│   │   └─ history_store.dart / sqflite_history_store.dart
│   └─ repositories/
│       ├─ translation_repository.dart         # 프롬프트 구성·후처리·추론 호출
│       ├─ model_repository.dart               # 상태 머신: 존재/다운로드/로드
│       └─ history_repository.dart
└─ presentation/
    ├─ setup/
    │   ├─ setup_screen.dart
    │   └─ setup_controller.dart
    ├─ translation/
    │   ├─ translation_screen.dart
    │   └─ translation_controller.dart
    └─ history/
        ├─ history_screen.dart
        └─ history_controller.dart
```

### 4.3 추론 인터페이스 (백엔드 교체 대비)

```dart
abstract class InferenceService {
  Future<bool> modelExists();
  Future<bool> isLoaded();
  Future<void> load(String modelPath);
  Future<String> translate({required String text, required LanguageDirection dir});
  Future<void> dispose();
}
```

MediaPipe 구현은 `MethodChannel`로 네이티브에 위임. 향후 LiteRT-LM 구현체를 새로 추가하고 바인딩만 교체하면 됨.

## 5. 데이터 흐름

### 5.1 번역 1회

```
[마이크 버튼] → ListenSpeech UseCase → SpeechService.listen(locale)
   → 부분결과 스트림 → ViewModel.sourceText 갱신(미리보기)
   → finalResult →
      TranslateText UseCase
        → TranslationRepository.translate(text, dir)
            → 프롬프트 구성 → InferenceService.translate → 응답 후처리(cleanResponse)
        → Result<TranslationResult>
   > **구현 참고**: 실제 구현에서 프롬프트 구성과 `cleanResponse`는 Android `MainActivity.kt` 및 iOS `GemmaInferenceHandler.swift` 네이티브 핸들러에서 처리하여 양 플랫폼 간 바이트 동일성을 보장한다. Dart `TranslationRepository`는 결과를 trim하여 `Result`로 감싸는 역할만 한다.
   → ViewModel.translatedText 갱신 → View 표시
   → SaveTranslation UseCase → HistoryRepository.save (자동 저장)
   → (옵션/자동) SpeakText UseCase → TtsService.speak(targetLocale)
```

### 5.2 모델 준비 (앱 시작 / 설정 화면)

```
EnsureModelReady UseCase
  → ModelRepository.status()
      notDownloaded → 설정 화면에서 다운로드 트리거
        → ModelDownloadService.download(url) [진행률/재개/취소]
        → 체크섬 검증 → ready
      ready/notLoaded → InferenceService.load(path) → loaded
  → loaded 시 번역 화면 진입
```

## 6. 에러 처리

- 모든 외부 실패(권한 거부, 네트워크, 모델 없음/손상, 추론 실패, DB 오류)를 **`Failure` 하위 타입**으로 통일.
- UseCase는 `Result<T>`(`Success`/`Failure`) 반환. 산발적 try/catch 제거.
- ViewModel은 `Result`를 받아 UI 상태(에러 배너/스낵바/재시도 버튼)로 변환.
- 네이티브 `PlatformException`은 Service 경계에서 `Failure`로 매핑.

| Failure | 발생 지점 | UI 처리 |
|---|---|---|
| PermissionFailure | 마이크 권한 | 권한 요청 안내 |
| NetworkFailure | 모델 다운로드 | 재시도/재개 |
| ModelFailure | 모델 없음/손상/로드 실패 | 설정 화면 유도 |
| InferenceFailure | 번역 실패 | 스낵바 + 재시도 |
| StorageFailure | 히스토리 DB | 비치명적 로그/토스트 |

## 7. 번역 히스토리

- **저장 시점**: 번역 성공 시 자동 저장.
- **스키마(sqflite)**: `id, source_text, translated_text, source_lang, target_lang, created_at`.
- **히스토리 화면**: 최신순 목록, 항목별 복사 / TTS 재생(언어 자동 판별) / 삭제, 전체 삭제.
- **추상화**: `HistoryStore` 인터페이스 → `SqfliteHistoryStore` 구현. 테스트는 인메모리 Fake로.

## 8. 모델 다운로드

- 모델 소스 URL은 **설정 가능**(기본값 1개 — Gemma 4 E2B `.task`). Gemma 라이선스/인증 토큰이 필요한 소스일 경우 헤더 주입 지점을 둔다.
- `http` 스트리밍 다운로드 + 바이트 진행률 + **Range 재개** + 취소 + **SHA-256 체크섬** 검증.
- 저장 위치: 앱 문서 디렉터리. 다운로드 완료/검증 후에만 `ready` 표시.
- 개발자/고급용 수동 파일 선택은 선택적 보조 경로로 남길 수 있음(기본 비노출).

## 9. iOS 추가 작업

- `inference_service`의 iOS 네이티브 구현: `MediaPipeTasksGenAI` Pod + Swift `MethodChannel` 핸들러를 Android `MainActivity.kt`와 **동형 API**로 작성.
- `Info.plist`에 마이크/음성인식 권한 문구 추가(`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`).
- STT(`speech_to_text`)/TTS(`flutter_tts`)는 iOS 지원 — 권한·로케일만 확인.

## 10. 테스트 전략

- **UseCase 단위 테스트**: Service/Repository를 Fake/Mock으로 주입. 번역/모델준비/히스토리 핵심 로직 커버.
- **Repository 테스트**: 프롬프트 구성·응답 후처리(`cleanResponse`), 히스토리 인메모리 store.
- **ViewModel 테스트**: GetX 컨트롤러 상태 전이(로딩/에러/성공).
- **위젯 스모크 테스트**: 각 화면 렌더링 + 기본 상호작용.
- 네이티브 추론 자체는 단위 테스트 대상 외(인터페이스 경계에서 Fake로 대체).

## 11. 의존성 변화

- 추가: `sqflite`, `path`(DB 경로), `crypto`(체크섬). `http`/`path_provider`는 기존.
- 유지: `get`, `speech_to_text`, `flutter_tts`, `permission_handler`, `file_picker`(보조).

## 12. 마이그레이션 / 작업 순서 (개략)

1. `core`(Result/Failure/Language) + 디렉터리 골격.
2. Service 인터페이스 + 기존 동작 래핑(STT/TTS/Inference).
3. Repository/UseCase 도입, `TranslationController` 분해.
4. 모델 다운로드 Service + 설정 화면 개편.
5. 히스토리(저장소 + 화면).
6. iOS 네이티브 추론 구현 + 권한.
7. 테스트 보강.

*상세 단계는 후속 구현 계획(plan) 문서에서 정의한다.*

## 13. 미해결/추후 후보

- 2인 대화형 화면, 토큰 스트리밍 동시통역, 클라우드 폴백, 모델 변형 선택(E4B) — 모두 범위 밖, 추후 검토.
