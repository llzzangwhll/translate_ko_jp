# iOS 네이티브 추론 — Mac 검증 체크리스트

Windows에서는 iOS 빌드/`pod install`/실행이 불가능하다. 아래 단계는 **macOS + Xcode + CocoaPods** 환경에서 수행한다. 대상: `ios/Runner/GemmaInferenceHandler.swift`, `ios/Runner/AppDelegate.swift`, `ios/Podfile`, `ios/Runner/Info.plist` (모두 커밋 완료, 빌드 미검증).

관련 메모리: 출시 전 후속 항목 참조.

## 0. 사전 준비

- [ ] macOS + 최신 Xcode + Command Line Tools 설치
- [ ] CocoaPods 설치 (`sudo gem install cocoapods` 또는 `brew install cocoapods`)
- [ ] Flutter가 Mac에서 동작 (`flutter doctor` 통과)
- [ ] 저장소 클론 후 `flutter pub get`

## 1. CocoaPods 의존성 설치

```bash
cd ios
pod install --repo-update
```

- [ ] `MediaPipeTasksGenAI` (`~> 0.10.22`)가 정상 설치되는지 확인
- [ ] 의존 C 코어(`MediaPipeTasksGenAIC`)가 자동 해결되는지 확인. 실패 시 `ios/Podfile`에 명시적으로 추가:
      `pod 'MediaPipeTasksGenAIC'` (Podfile 주석 참고)
- [ ] `Runner.xcworkspace`가 생성/갱신됨 (이후 항상 `.xcworkspace`로 연다)
- [ ] 배포 타깃이 **iOS 16.0** 이상으로 설정됨 (Podfile `platform :ios, '16.0'` + `post_install`의 `IPHONEOS_DEPLOYMENT_TARGET`)

## 2. Swift API 시그니처 확인 (설치된 Pod 헤더와 대조)

`GemmaInferenceHandler.swift`가 사용하는 API가 설치된 `MediaPipeTasksGenAI 0.10.22`와 일치하는지 빌드로 확인한다.

```bash
cd ..
flutter build ios --debug --no-codesign
```

- [ ] `LlmInference.Options(modelPath:)` 이니셜라이저가 존재하고 컴파일됨
- [ ] `options.maxTokens = 512` 설정 가능한 속성인지 확인
- [ ] `try LlmInference(options:)` (throwing init) 시그니처 일치
- [ ] `inference.generateResponse(inputText:)` (throwing) 메서드명/라벨 일치
- [ ] `llmInference?.close()` 가 유효 (reload 시 이전 인스턴스 해제 — Android 동형). 만약 메서드명이 다르면(`cancel()`/`invalidate()` 등) 해당 API로 교체
- [ ] 빌드가 에러 없이 완료

> API가 다르면 `GemmaInferenceHandler.swift`의 해당 호출만 설치된 Pod 시그니처에 맞춰 수정한다. MethodChannel 계약(메서드명/에러코드/프롬프트/cleanResponse)은 절대 바꾸지 않는다 — Android(`MainActivity.kt`)와 바이트 동일해야 한다.

## 3. 권한 다이얼로그 (Info.plist)

- [ ] 시뮬레이터/디바이스에서 STT 첫 사용 시 `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription` 문구가 한국어+영어로 정상 노출
- [ ] (마이크 권한 UX #2 구현 후) 권한 거부→설정 안내 흐름이 iOS에서도 동작

## 4. 모델 파일 배치 & 채널 스모크

iOS 추론은 앱 문서 디렉터리에서 모델을 찾는다 (`findModelFile()`가 `documentDirectory` 우선 검색 — 인앱 다운로더가 쓰는 위치와 동일). 탐색 확장자는 `.litertlm` / `.task` / `.bin`.

> **(중요) Gemma 4 E2B는 `.litertlm`(LiteRT-LM) 형식으로 배포된다.** 네이티브 핸들러는
> `.litertlm` 파일을 찾아 명시 경로로 `LlmInference`에 넘긴다. **설치된 MediaPipe
> `tasks-genai 0.10.22`가 `.litertlm` 콘텐츠를 실제로 로드하는지 반드시 기기에서 확인**한다.
> - 로드 성공 → 그대로 사용.
> - `loadModel`이 실패(`LOAD_FAILED`)하면 MediaPipe가 해당 형식을 지원하지 않는 것이므로,
>   (a) 웹 변형 `gemma-4-E2B-it-web.task`를 시도하거나, (b) 추론 백엔드를 **LiteRT-LM**으로
>   이전(옵션 C)해야 한다. `InferenceService` 인터페이스 뒤로 추상화돼 있어 교체 가능.

- [ ] 인앱 다운로드(설정 화면)로 모델을 받거나, 시뮬레이터의 앱 Documents 디렉터리에 알려진 파일명(예: `gemma-4-E2B-it.litertlm` 또는 `MODEL_NAMES` 목록 중 하나)으로 수동 배치
- [ ] `checkModelExists` → `true` 반환 확인
- [ ] `loadModel` → 성공(`true`), 잘못된/빈 파일이면 `MODEL_NOT_FOUND`/`LOAD_FAILED`
- [ ] 로드 전에 `translate` 호출 시 `NOT_LOADED` 에러
- [ ] 로드 후 한국어 입력 → 일본어 번역 문자열 반환, 그 반대도 확인
- [ ] 추론이 메인 스레드를 막지 않음(UI 응답 유지), 결과는 메인에서 콜백

## 5. Dart 계약 스모크 테스트 (시뮬레이터)

```bash
flutter test integration_test/ios_channel_smoke_test.dart -d <simulator-id>
```

- [ ] 채널 `com.example.translate_ko_jp/gemma` 응답, 인자 전달(`text`/`sourceLang`/`targetLang`) 검증 통과

## 6. 회귀

- [ ] `flutter test` (전체) Mac에서도 그린
- [ ] `flutter build ios --release --no-codesign` 성공(서명 제외)

## 알려진 제약 / 후속

- Swift 6 strict concurrency로 가면 `llmInference` 비동기 접근(로드 vs 번역)이 데이터 레이스로 플래그될 수 있음 — 필요 시 액터/직렬 큐로 보호. 현재 호출 패턴(순차)에서는 실사용 위험 낮음.
- MediaPipe LLM Inference API는 maintenance-only — 장기적으로 LiteRT-LM 이전 검토(`InferenceService` 인터페이스 뒤로 추상화되어 있어 교체 용이).
