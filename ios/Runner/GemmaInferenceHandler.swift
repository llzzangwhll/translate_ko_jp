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
                self.llmInference?.close()
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

    // MARK: - 내부 유틸: 에러를 메인 스레드에서 반환

    private func fail(_ result: @escaping FlutterResult, code: String, message: String) {
        DispatchQueue.main.async {
            result(FlutterError(code: code, message: message, details: nil))
        }
    }
}
