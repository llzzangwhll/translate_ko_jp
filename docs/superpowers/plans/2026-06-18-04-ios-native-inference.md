# iOS 네이티브 추론 (iOS Native Inference) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS 네이티브에서 MediaPipe `LlmInference`(Gemma 4 E2B)를 구동하고, Android `MainActivity.kt`와 동형인 `com.example.translate_ko_jp/gemma` MethodChannel을 Swift 핸들러로 구현한다.

**Architecture:** `AppDelegate`는 채널 등록과 라우팅만 담당하고, 추론 로직(`LlmInference` 보유, 모델 탐색/로딩/번역, 프롬프트 빌드, 응답 정제)은 단일 책임을 갖는 `GemmaInferenceHandler` 클래스로 분리한다. 로드/번역 작업은 백그라운드 `DispatchQueue`에서 실행하고 결과는 `DispatchQueue.main`에서 `FlutterResult`로 반환하여 Android의 executor + mainHandler 패턴을 그대로 미러링한다. 에러 코드(`MODEL_NOT_FOUND`/`LOAD_FAILED`/`NOT_LOADED`/`TRANSLATE_FAILED`)와 프롬프트/정제 로직은 Android와 글자 단위로 동일하게 맞춘다.

**Tech Stack:** iOS, Swift, MediaPipeTasksGenAI (CocoaPods), Flutter MethodChannel

---

## 사전 메모 (worker 필독)

- **현재 상태:** `ios/Runner/AppDelegate.swift`에는 이미 동작하는 인라인 구현이 들어 있다(채널 등록 + 추론 로직이 한 파일에 섞여 있음). 이 plan은 추론 로직을 **별도 `GemmaInferenceHandler.swift`로 추출**하고, `AppDelegate`는 채널 등록·핸들러 부착만 남기도록 리팩터링한다. 동작은 보존하되 책임을 분리하는 것이 목표다.
- **MethodChannel 계약(고정):** 채널 `com.example.translate_ko_jp/gemma`, 메서드 `checkModelExists → bool`, `isModelLoaded → bool`, `loadModel({modelPath?}) → bool`, `translate({text, sourceLang, targetLang}) → String`. `sourceLang`/`targetLang`는 `"Korean"` | `"Japanese"` (= Dart `Language.promptLabel`). 이 계약은 plan 00 INDEX의 "MethodChannel 계약"이 단일 진실 공급원이며 변경 금지.
- **Mac 의존성:** iOS 네이티브 빌드와 MediaPipe Pod 설치는 macOS + Xcode + CocoaPods가 필요하다. 개발 머신이 Windows이므로 빌드/실행 검증은 **수동(Mac 필요)** 단계로 정직하게 표기한다. 가짜 통과 테스트를 만들지 않는다.
- **건드리지 않는 것:** Dart 비즈니스 로직(MethodChannel 래퍼는 plan 01 소관). 이 plan은 iOS 네이티브 파일 + `Podfile` + `Info.plist`만 수정한다.
- **병렬성:** 이 plan은 고정된 MethodChannel 계약에만 의존하므로 01–03과 병렬 진행 가능.

---

## Android 참조 동작 (반드시 동일하게 유지)

`android/.../MainActivity.kt` 기준 — iOS Swift가 미러링해야 하는 정확한 동작:

- **MODEL_NAMES (탐색 우선순위 동일):**
  ```
  gemma3-1B-it-int4.task
  gemma-2b-it-gpu-int4.bin
  gemma-2b-it-cpu-int4.bin
  gemma3-1b-it-int4.bin
  model.bin
  model.task
  ```
- **MODEL_EXTENSIONS:** `bin`, `task`
- **loadModel:** `modelPath` 인자 우선, 없으면 자동 탐색 → 파일 없거나 크기 0이면 `MODEL_NOT_FOUND` → 이전 인스턴스 close → `LlmInference.Options(modelPath:)` + `maxTokens = 512` → 생성 성공 시 `true`. 예외는 `LOAD_FAILED`.
- **translate:** `llmInference == null`이면 `NOT_LOADED` 즉시 반환 → `buildTranslationPrompt` → `generateResponse` → `cleanResponse` → 성공 시 cleaned String. 예외는 `TRANSLATE_FAILED`.
- **buildTranslationPrompt:** sourceLang/targetLang(`"Korean"`/`"Japanese"`)를 `한국어`/`日本語` 라벨로 매핑 후 아래 정확한 형식:
  ```
  Translate the following <source> text to <target>. Output ONLY the translation, nothing else.

  <source>: <text>
  <target>:
  ```
- **cleanResponse:** trim → 접두어 `["한국어:", "日本語:", "Korean:", "Japanese:", "Translation:"]`를 대소문자 무시로 stripping → 첫 비공백 라인만 취함.

---

## Task 1 — Podfile: MediaPipe Pod & iOS 최소 버전

**Files:**
- Modify: `ios/Podfile`

**배경:** MediaPipe GenAI(`LlmInference`)는 최신 iOS를 요구한다. MediaPipeTasksGenAI 0.10.x는 **iOS 15.0 이상**을 최소 배포 타깃으로 요구한다(공식 podspec 기준 `ios.deployment_target = '15.0'`). 현재 Podfile은 이미 `platform :ios, '16.0'`으로 설정되어 있어 요건(15+)을 충족하므로 **다운그레이드하지 말 것**. 16.0을 유지하되, post_install에서 모든 Pods 타깃의 `IPHONEOS_DEPLOYMENT_TARGET`을 최소 15.0 이상으로 강제하여 일부 의존 Pod가 더 낮은 타깃으로 떨어지는 경우를 방지한다.

> 결론(검증된 텍스트): **요구 최소 = iOS 15.0**, 본 프로젝트는 **iOS 16.0**을 사용(요건 충족). Xcode 프로젝트 `IPHONEOS_DEPLOYMENT_TARGET`도 16.0으로 맞춰야 한다(Task 6 참조).

**현재 Podfile은 이미 `MediaPipeTasksGenAI`를 포함**하고 있다. 따라서 이 Task는 (a) 버전/플랫폼이 올바른지 확인하고 (b) `MediaPipeTasksGenAIC`가 필요한 경우의 처리와 (c) post_install의 deployment target 강제만 보강한다.

**Steps:**

1. - [ ] `ios/Podfile` 1행이 `platform :ios, '16.0'`인지 확인한다(이미 그렇다면 변경 없음). 15.0 미만이면 `'16.0'`으로 올린다.
2. - [ ] `target 'Runner'` 블록 내 Pod 선언이 아래와 같은지 확인/수정한다. `MediaPipeTasksGenAIC`는 보통 `MediaPipeTasksGenAI`의 의존성으로 자동 설치되므로 **명시 선언은 불필요**하다. 다만 CocoaPods가 C 모듈을 찾지 못해 `pod install`이 실패하는 경우에만 주석을 해제한다.

   ```ruby
   target 'Runner' do
     use_frameworks!
     use_modular_headers!

     flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))

     # MediaPipe LLM Inference (Gemma on-device)
     pod 'MediaPipeTasksGenAI', '~> 0.10.22'
     # 아래는 MediaPipeTasksGenAI의 의존성으로 자동 설치된다.
     # `pod install`이 C 코어 모듈을 찾지 못한다고 실패할 때만 주석 해제:
     # pod 'MediaPipeTasksGenAIC', '~> 0.10.22'
   end
   ```

3. - [ ] `post_install` 블록을 아래로 교체하여 모든 Pods 타깃의 배포 타깃을 16.0 이상으로 강제한다(낮게 떨어지는 Pod 방지).

   ```ruby
   post_install do |installer|
     installer.pods_project.targets.each do |target|
       flutter_additional_ios_build_settings(target)
       target.build_configurations.each do |config|
         # MediaPipe GenAI 요구 최소(15.0)를 충족하도록 강제. 프로젝트 타깃과 동일하게 16.0 사용.
         current = config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']
         if current.nil? || current.to_f < 16.0
           config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
         end
       end
     end
   end
   ```

**Verification:**

4. - [ ] (Windows에서 가능) 파일 정적 점검: `ios/Podfile`에 `platform :ios, '16.0'`, `pod 'MediaPipeTasksGenAI'`, post_install의 `IPHONEOS_DEPLOYMENT_TARGET` 강제 라인이 존재함을 확인한다.
5. - [ ] **(Mac 필요)** `cd ios && pod repo update && pod install` 실행 → `MediaPipeTasksGenAI`(및 자동 의존 `MediaPipeTasksGenAIC`, `MediaPipeTasksGenAICShared` 등)가 `Pods/`에 설치되고 `Podfile.lock`에 기록되는지 확인. 에러 없이 `Pod installation complete!` 출력이면 통과.

---

## Task 2 — GemmaInferenceHandler.swift 생성 (추론 로직 추출)

**Files:**
- Create: `ios/Runner/GemmaInferenceHandler.swift`

**설계:** Android의 `executor`(단일 백그라운드 스레드) + `mainHandler`(메인 복귀) 패턴을 `DispatchQueue(label:)` + `DispatchQueue.main`으로 미러링한다. 핸들러는 `handle(call:result:)` 단일 진입점을 제공하여 `AppDelegate`가 `setMethodCallHandler`에서 그대로 위임할 수 있게 한다. 모든 에러 코드/메시지/프롬프트/정제 로직은 Android와 동일하다.

**Steps:**

1. - [ ] 아래 **완전한** 내용으로 `ios/Runner/GemmaInferenceHandler.swift`를 생성한다.

```swift
import Foundation
import Flutter
import MediaPipeTasksGenAI

/// Gemma on-device 추론 핸들러.
/// Android `MainActivity.kt`와 동형: 동일 채널 메서드, 동일 에러 코드,
/// 동일 프롬프트/응답 정제 로직, 백그라운드 실행 + 메인 스레드 결과 반환.
final class GemmaInferenceHandler {

    // MARK: - 상수 (Android MODEL_NAMES / MODEL_EXTENSIONS와 동일 순서/값)

    private static let modelNames = [
        "gemma3-1B-it-int4.task",
        "gemma-2b-it-gpu-int4.bin",
        "gemma-2b-it-cpu-int4.bin",
        "gemma3-1b-it-int4.bin",
        "model.bin",
        "model.task"
    ]

    private static let modelExtensions = ["bin", "task"]

    private static let maxTokens = 512

    // MARK: - 상태

    private var llmInference: LlmInference?

    /// Android의 single-thread executor에 대응 (직렬 큐).
    private let queue = DispatchQueue(label: "com.example.translate_ko_jp.gemma", qos: .userInitiated)

    // MARK: - 단일 진입점 (AppDelegate가 위임)

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "checkModelExists":
            result(findModelFile() != nil)

        case "isModelLoaded":
            result(llmInference != nil)

        case "loadModel":
            loadModel(call: call, result: result)

        case "translate":
            translate(call: call, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - loadModel

    private func loadModel(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        let explicitPath = args?["modelPath"] as? String

        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                // 명시 경로 우선, 없으면 자동 탐색 (Android와 동일)
                let modelPath = explicitPath ?? self.findModelFile()

                guard let path = modelPath else {
                    self.fail(result, code: "MODEL_NOT_FOUND",
                              message: "모델 파일을 찾을 수 없습니다.")
                    return
                }

                let fileManager = FileManager.default
                let attrs = try? fileManager.attributesOfItem(atPath: path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                if !fileManager.fileExists(atPath: path) || size == 0 {
                    self.fail(result, code: "MODEL_NOT_FOUND",
                              message: "모델 파일이 존재하지 않거나 비어있습니다: \(path)")
                    return
                }

                NSLog("[GemmaTranslator] Loading model from: \(path) (\(size / 1024 / 1024)MB)")

                // 이전 인스턴스 정리 (Android llmInference?.close()에 대응)
                self.llmInference = nil

                let options = LlmInference.Options(modelPath: path)
                options.maxTokens = GemmaInferenceHandler.maxTokens

                self.llmInference = try LlmInference(options: options)
                NSLog("[GemmaTranslator] Model loaded successfully")

                DispatchQueue.main.async { result(true) }
            } catch {
                NSLog("[GemmaTranslator] Failed to load model: \(error)")
                self.fail(result, code: "LOAD_FAILED",
                          message: "모델 로딩 실패: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - translate

    private func translate(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let text = args["text"] as? String ?? ""
        let sourceLang = args["sourceLang"] as? String ?? "Korean"
        let targetLang = args["targetLang"] as? String ?? "Japanese"

        guard let inference = llmInference else {
            // Android와 동일하게 메인 스레드에서 즉시 에러 반환.
            result(FlutterError(code: "NOT_LOADED",
                                message: "모델이 로드되지 않았습니다",
                                details: nil))
            return
        }

        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let prompt = self.buildTranslationPrompt(text: text,
                                                         sourceLang: sourceLang,
                                                         targetLang: targetLang)
                NSLog("[GemmaTranslator] Prompt: \(prompt)")

                let response = try inference.generateResponse(inputText: prompt)
                let cleaned = self.cleanResponse(response, targetLang: targetLang)
                NSLog("[GemmaTranslator] Response: \(cleaned)")

                DispatchQueue.main.async { result(cleaned) }
            } catch {
                NSLog("[GemmaTranslator] Translation failed: \(error)")
                self.fail(result, code: "TRANSLATE_FAILED",
                          message: "번역 실패: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 모델 파일 탐색 (Android findModelFile 미러링)

    private func findModelFile() -> String? {
        let fileManager = FileManager.default
        var searchDirs: [String] = []

        // 앱 Documents 디렉터리 (plan 02 인앱 다운로더가 .task를 여기에 기록).
        // Flutter path_provider getApplicationDocumentsDirectory()와 동일 경로.
        if let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.path {
            searchDirs.append(docDir)
            searchDirs.append((docDir as NSString).appendingPathComponent("models"))
        }

        // 앱 Application Support 디렉터리 (path_provider getApplicationSupportDirectory()).
        if let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path {
            searchDirs.append(supportDir)
            searchDirs.append((supportDir as NSString).appendingPathComponent("models"))
        }

        // 앱 번들 (테스트용으로 모델을 번들에 동봉한 경우).
        if let bundlePath = Bundle.main.resourcePath {
            searchDirs.append(bundlePath)
        }

        // 1) 알려진 모델 이름 우선 탐색 (Android와 동일 우선순위).
        for dir in searchDirs {
            for name in GemmaInferenceHandler.modelNames {
                let path = (dir as NSString).appendingPathComponent(name)
                if fileExistsNonEmpty(path) {
                    return path
                }
            }
        }

        // 2) Documents / Application Support 내 임의의 .bin / .task 스캔.
        for dir in searchDirs {
            guard let files = try? fileManager.contentsOfDirectory(atPath: dir) else { continue }
            for file in files {
                let ext = (file as NSString).pathExtension.lowercased()
                if GemmaInferenceHandler.modelExtensions.contains(ext) {
                    let path = (dir as NSString).appendingPathComponent(file)
                    if fileExistsNonEmpty(path) {
                        return path
                    }
                }
            }
        }

        return nil
    }

    private func fileExistsNonEmpty(_ path: String) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else { return false }
        let attrs = try? fileManager.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        return size > 0
    }

    // MARK: - 프롬프트 빌드 (Android buildTranslationPrompt와 글자 단위 동일)

    private func buildTranslationPrompt(text: String, sourceLang: String, targetLang: String) -> String {
        let sourceLabel = sourceLang == "Korean" ? "한국어" : "日本語"
        let targetLabel = targetLang == "Korean" ? "한국어" : "日本語"

        return """
        Translate the following \(sourceLabel) text to \(targetLabel). Output ONLY the translation, nothing else.

        \(sourceLabel): \(text)
        \(targetLabel):
        """
    }

    // MARK: - 응답 정제 (Android cleanResponse와 동일)

    private func cleanResponse(_ response: String, targetLang: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["한국어:", "日本語:", "Korean:", "Japanese:", "Translation:"]
        for prefix in prefixes {
            if cleaned.lowercased().hasPrefix(prefix.lowercased()) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        // 첫 번째 비공백 라인만 취함 (Android lines().firstOrNull { isNotBlank }).
        if let firstLine = cleaned
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            cleaned = firstLine.trimmingCharacters(in: .whitespaces)
        }
        return cleaned
    }
}
```

**Verification:**

2. - [ ] (Windows에서 가능) 정적 대조: 파일에 `MODEL_NOT_FOUND`, `LOAD_FAILED`, `NOT_LOADED`, `TRANSLATE_FAILED` 4개 에러 코드가 모두 존재하고, `buildTranslationPrompt`/`cleanResponse`의 텍스트가 `MainActivity.kt`와 동일한지 비교한다(접두어 배열, 프롬프트 형식 문자열).
3. - [ ] (Windows에서 가능) `maxTokens = 512`, `modelNames` 6개 항목 순서가 Android `MODEL_NAMES`와 일치하는지 확인.
4. - [ ] **(Mac 필요)** Xcode에서 컴파일 에러 없이 빌드되는지 확인(Task 6의 빌드 단계에서 함께 검증). `LlmInference.Options`, `generateResponse(inputText:)` API 시그니처가 설치된 Pod 버전과 일치해야 한다.

---

## Task 3 — AppDelegate.swift: 채널 등록 + 핸들러 위임으로 슬림화

**Files:**
- Modify: `ios/Runner/AppDelegate.swift`

**설계:** 추론 로직을 모두 `GemmaInferenceHandler`로 옮겼으므로 `AppDelegate`는 (a) 플러그인 등록, (b) 채널 생성, (c) 핸들러 인스턴스 보유 및 위임만 남긴다. `GeneratedPluginRegistrant.register`는 유지한다.

**Steps:**

1. - [ ] `ios/Runner/AppDelegate.swift` 전체를 아래 **완전한** 내용으로 교체한다.

```swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

    private let gemmaHandler = GemmaInferenceHandler()

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            fatalError("rootViewController is not a FlutterViewController")
        }

        let channel = FlutterMethodChannel(
            name: "com.example.translate_ko_jp/gemma",
            binaryMessenger: controller.binaryMessenger
        )

        channel.setMethodCallHandler { [weak self] (call, result) in
            self?.gemmaHandler.handle(call, result: result)
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
```

**Verification:**

2. - [ ] (Windows에서 가능) 정적 점검: `AppDelegate.swift`에 채널명 문자열 `com.example.translate_ko_jp/gemma`가 정확히 존재하고, 추론 로직(`buildPrompt`, `cleanResponse`, `findModelFile`, `LlmInference`)이 **더 이상 이 파일에 없음**(전부 핸들러로 이동)을 확인한다. `import MediaPipeTasksGenAI`는 AppDelegate에서 제거됨.
3. - [ ] **(Mac 필요)** Xcode 빌드 통과 확인(Task 6).

---

## Task 4 — Info.plist 권한 키 (마이크 + 음성 인식)

**Files:**
- Modify: `ios/Runner/Info.plist`

**배경:** `speech_to_text` 플러그인(plan 01에서 사용)이 STT를 위해 마이크/음성 인식 권한을 요구한다. 권한 사유 문자열은 한국어 + 일본어 사용자 친화적 영문을 함께 제공한다.

> **현재 상태:** `Info.plist`에는 이미 한국어 `NSSpeechRecognitionUsageDescription`/`NSMicrophoneUsageDescription`가 존재한다. 이 Task는 한↔일 번역 앱 성격에 맞게 **한국어 + 영어 병기** 사유 문자열로 갱신한다(일본어 사용자도 이해 가능한 친화적 문구).

**Steps:**

1. - [ ] `ios/Runner/Info.plist`에서 기존 두 키의 `<string>` 값을 아래로 교체한다(키 자체는 그대로). 키가 없을 경우 `</dict>` 직전에 두 블록 모두 추가한다.

   기존:
   ```xml
   	<key>NSSpeechRecognitionUsageDescription</key>
   	<string>음성을 텍스트로 변환하여 번역하기 위해 음성 인식 권한이 필요합니다.</string>
   	<key>NSMicrophoneUsageDescription</key>
   	<string>음성 입력을 위해 마이크 권한이 필요합니다.</string>
   ```

   교체 후:
   ```xml
   	<key>NSSpeechRecognitionUsageDescription</key>
   	<string>음성을 텍스트로 변환해 번역하기 위해 음성 인식 권한이 필요합니다. / Speech recognition is used to transcribe your voice for Korean–Japanese translation.</string>
   	<key>NSMicrophoneUsageDescription</key>
   	<string>음성 입력을 받기 위해 마이크 권한이 필요합니다. / The microphone is used to capture your voice for translation.</string>
   ```

**Verification:**

2. - [ ] (Windows에서 가능) `ios/Runner/Info.plist`가 유효한 XML이며 `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` 두 키가 정확히 한 번씩 존재함을 확인한다(중복 키 금지 — plist 중복 키는 빌드 경고/런타임 문제 유발).
3. - [ ] **(Mac 필요)** 실기기에서 STT 최초 사용 시 마이크/음성 인식 권한 다이얼로그가 위 문구로 뜨는지 확인.

---

## Task 5 — 모델 배치 가이드 (테스트용 .task 모델)

**Files:**
- (문서 전용 — 코드 변경 없음. 본 Task는 절차 검증만 수행)

**배경:** plan 02의 인앱 다운로더는 모델을 **앱 Documents 디렉터리**(`getApplicationDocumentsDirectory()`)에 기록한다. iOS 핸들러의 `findModelFile()`은 Documents + Documents/models + Application Support + 앱 번들을 탐색하므로 다운로더 출력 위치를 커버한다. 파일명 규약은 Android `MODEL_NAMES`와 동일하게 유지한다(특히 1순위 `gemma3-1B-it-int4.task`).

**Gemma 4 E2B `.task` 모델 확보/배치 방법 (테스트 시):**

- **권장 (실 사용 경로):** 앱 실행 → 설정 화면에서 plan 02 인앱 다운로더로 다운로드. 모델이 Documents에 저장되고 핸들러가 자동 인식.
- **수동 (시뮬레이터/개발 편의):** 다운로더 없이 테스트하려면 모델 `.task` 파일을 다음 중 한 곳에 배치한다:
  1. **시뮬레이터 Documents:** 앱을 한 번 실행해 컨테이너를 만든 뒤, Xcode → Window → Devices and Simulators → 해당 시뮬레이터 → 앱 컨테이너로 push, 또는 시뮬레이터 데이터 경로 `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application/<APP-UUID>/Documents/`에 복사. 파일명은 `gemma3-1B-it-int4.task`(1순위) 권장.
  2. **앱 번들 동봉(읽기 전용 테스트):** `.task`를 `ios/Runner`에 추가하고 Xcode "Copy Bundle Resources"에 포함. 핸들러가 `Bundle.main.resourcePath`도 탐색하므로 인식됨. (실 배포에는 비권장 — 바이너리 비대.)
- **파일명 규약(Android와 공유):** 우선순위 1위 `gemma3-1B-it-int4.task`. 그 외 허용 이름은 Android `MODEL_NAMES` 목록과 동일. 확장자는 `.task` 또는 `.bin`.

> **주의:** Gemma 4 E2B 모델은 Hugging Face / Kaggle의 라이선스 동의가 필요하다. 모델 가중치 URL/체크섬은 plan 02의 다운로더 설정에 둔다(이 plan에 하드코딩하지 않음).

**Steps:**

1. - [ ] (Windows에서 가능) `findModelFile()`의 탐색 디렉터리에 Documents가 포함되어 있고, 이것이 plan 02 다운로더의 기록 위치(`getApplicationDocumentsDirectory`)와 일치함을 코드로 재확인한다.
2. - [ ] **(Mac 필요)** 위 수동 배치 절차 중 하나로 시뮬레이터/기기에 `.task`를 두고, 앱에서 `checkModelExists`가 `true`를 반환하는지 확인(Task 6 스모크).

---

## Task 6 — 빌드 & 실행 검증 + 크로스플랫폼 스모크 체크

**Files:**
- (검증 전용. 단, Dart 스모크 테스트를 작성한다면 Create: `integration_test/ios_channel_smoke_test.dart` — 아래 참조)

**정직성 고지:** Swift 네이티브 코드의 진짜 단위 테스트는 이 환경(Windows)에서 불가능하다. 따라서 핵심 검증은 **(A) Mac에서의 빌드+실기/시뮬 수동 실행** + **(B) 플랫폼 무관한 Dart 측 MethodChannel 계약 스모크**다. 가짜 통과 테스트를 만들지 않는다.

### (A) Mac 빌드/실행 검증 (Mac 필요)

1. - [ ] **(Mac 필요)** `flutter pub get` → `cd ios && pod install` 성공.
2. - [ ] **(Mac 필요)** `flutter build ios --debug --no-codesign` (또는 Xcode에서 Runner 스킴 빌드) 에러 없이 통과. `GemmaInferenceHandler.swift`가 컴파일되고 `LlmInference.Options(modelPath:)` / `generateResponse(inputText:)` API가 설치된 Pod와 일치하는지 확인.
3. - [ ] **(Mac 필요)** 시뮬레이터/실기 실행 후 채널 스모크:
   - 모델 미배치 상태: `isModelLoaded` → `false`, `checkModelExists` → `false`.
   - `.task` 배치 후: `checkModelExists` → `true`, `loadModel` → `true`, `isModelLoaded` → `true`.
   - `translate(text:"안녕하세요", sourceLang:"Korean", targetLang:"Japanese")` → 일본어 문자열 반환(예: "こんにちは" 계열).
   - 모델 로드 전 `translate` 호출 → `NOT_LOADED` FlutterError.

### (B) Dart 측 계약 스모크 (크로스플랫폼 — Windows에서도 작성/실행 가능)

이 스모크는 **MethodChannel 계약**(채널명/메서드명/응답 타입)을 Dart에서 검증한다. 실제 네이티브를 호출하지 않고 `TestDefaultBinaryMessengerBinding`으로 채널을 모킹하여, plan 01의 Dart 래퍼가 동일 계약(`isModelLoaded` → bool 등)을 기대하는지 확인한다. 네이티브 정답이 아니라 **계약 합치 여부**를 본다.

> **선행 의존:** 실제 Dart 래퍼(`InferenceService`의 MethodChannel 구현)는 plan 01 산출물이다. plan 01이 아직 없으면 이 스모크는 **채널명 상수만** 검증하는 최소형으로 시작하고, plan 01 머지 후(또는 plan 05 통합) 확장한다.

4. - [ ] (선택, Windows 가능) `integration_test/ios_channel_smoke_test.dart`에 아래 최소 스모크를 작성한다. 이는 채널이 모킹 시 `isModelLoaded=false`(로드 전), `checkModelExists=false`를 반환하도록 하고 래퍼가 이를 그대로 노출하는지 본다.

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.translate_ko_jp/gemma');
  final log = <MethodCall>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      switch (call.method) {
        case 'isModelLoaded':
          return false; // 로드 전 false (계약)
        case 'checkModelExists':
          return false; // 모델 미배치 false (계약)
        case 'loadModel':
          return true;
        case 'translate':
          return 'こんにちは';
        default:
          return null;
      }
    });
    log.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('isModelLoaded returns false before load (contract)', () async {
    final loaded = await channel.invokeMethod<bool>('isModelLoaded');
    expect(loaded, isFalse);
    expect(log.single.method, 'isModelLoaded');
  });

  test('translate passes Korean/Japanese promptLabels (contract)', () async {
    final out = await channel.invokeMethod<String>('translate', {
      'text': '안녕하세요',
      'sourceLang': 'Korean',
      'targetLang': 'Japanese',
    });
    expect(out, isA<String>());
    final args = log.single.arguments as Map;
    expect(args['sourceLang'], 'Korean');
    expect(args['targetLang'], 'Japanese');
  });
}
```

5. - [ ] (Windows 가능) `flutter test integration_test/ios_channel_smoke_test.dart` 실행 → 두 테스트 통과. (주의: 이 스모크는 채널 계약만 검증하며 네이티브 Swift 동작을 증명하지 않는다 — 정직성 한계.)
6. - [ ] **(Mac 필요)** 위 (A) 실기/시뮬 스모크가 실제 네이티브 경로를 검증하는 유일한 수단임을 PR 설명에 명시한다.

---

## 완료 기준 (Definition of Done)

- [ ] `ios/Podfile`: `platform :ios, '16.0'`(≥ MediaPipe 요구 최소 15.0), `pod 'MediaPipeTasksGenAI'` 포함, post_install이 모든 Pods 타깃 `IPHONEOS_DEPLOYMENT_TARGET`을 16.0 이상으로 강제.
- [ ] `ios/Runner/GemmaInferenceHandler.swift` 생성: `LlmInference?` 보유, 백그라운드 큐 실행 + 메인 스레드 결과 반환, `checkModelExists`/`isModelLoaded`/`loadModel(modelPath?)`/`translate(text,sourceLang,targetLang)` 구현, `maxTokens=512`.
- [ ] 에러 코드 `MODEL_NOT_FOUND`/`LOAD_FAILED`/`NOT_LOADED`/`TRANSLATE_FAILED`가 Android와 동일하게 반환됨.
- [ ] `buildTranslationPrompt`/`cleanResponse`가 Android `MainActivity.kt`와 글자 단위로 동일(프롬프트 형식, 접두어 배열, 첫 비공백 라인 추출).
- [ ] `modelNames` 6개 항목·순서가 Android `MODEL_NAMES`와 동일, `findModelFile`이 Documents(= plan 02 다운로더 출력 위치) + Application Support + 번들을 탐색.
- [ ] `ios/Runner/AppDelegate.swift`가 채널 `com.example.translate_ko_jp/gemma`를 등록하고 `GemmaInferenceHandler.handle`로 위임(추론 로직은 AppDelegate에 없음).
- [ ] `ios/Runner/Info.plist`에 `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`가 한국어+영어 병기로 각각 한 번씩 존재(중복 키 없음).
- [ ] 모델 배치 가이드 문서화: Documents 우선, 파일명 `gemma3-1B-it-int4.task`(1순위), Android 규약과 일치.
- [ ] **(Mac 필요)** `pod install` → Xcode 빌드 → 실기/시뮬에서 채널 스모크(미로드 시 `isModelLoaded=false`, 로드 후 `translate` 일본어 반환) 통과.
- [ ] (크로스플랫폼) Dart 계약 스모크 `flutter test integration_test/ios_channel_smoke_test.dart` 통과(채널 계약 검증, 네이티브 동작 증명 아님 — 정직히 표기).
- [ ] Dart 비즈니스 로직 미변경(이 plan은 iOS 네이티브 + Podfile + Info.plist만 수정).
