import Flutter
import UIKit
import MediaPipeTasksGenAI

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var llmInference: LlmInference?
    private let queue = DispatchQueue(label: "com.example.gemma", qos: .userInitiated)

    private let modelNames = [
        "gemma3-1B-it-int4.task",
        "gemma-2b-it-gpu-int4.bin",
        "gemma-2b-it-cpu-int4.bin",
        "gemma3-1b-it-int4.bin",
        "model.bin",
        "model.task"
    ]

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        let controller = window?.rootViewController as! FlutterViewController
        let channel = FlutterMethodChannel(
            name: "com.example.translate_ko_jp/gemma",
            binaryMessenger: controller.binaryMessenger
        )

        channel.setMethodCallHandler { [weak self] (call, result) in
            guard let self = self else { return }

            switch call.method {
            case "checkModelExists":
                result(self.findModelFile() != nil)

            case "loadModel":
                self.queue.async {
                    do {
                        let args = call.arguments as? [String: Any]
                        let modelPath = args?["modelPath"] as? String ?? self.findModelFile()

                        guard let path = modelPath else {
                            DispatchQueue.main.async {
                                result(FlutterError(
                                    code: "MODEL_NOT_FOUND",
                                    message: "모델 파일을 찾을 수 없습니다.",
                                    details: nil
                                ))
                            }
                            return
                        }

                        self.llmInference?.close()

                        let options = LlmInference.Options(modelPath: path)
                        options.maxTokens = 512

                        self.llmInference = try LlmInference(options: options)

                        DispatchQueue.main.async { result(true) }
                    } catch {
                        DispatchQueue.main.async {
                            result(FlutterError(
                                code: "LOAD_FAILED",
                                message: "모델 로딩 실패: \(error.localizedDescription)",
                                details: nil
                            ))
                        }
                    }
                }

            case "translate":
                let args = call.arguments as? [String: Any] ?? [:]
                let text = args["text"] as? String ?? ""
                let sourceLang = args["sourceLang"] as? String ?? "Korean"
                let targetLang = args["targetLang"] as? String ?? "Japanese"

                guard let inference = self.llmInference else {
                    result(FlutterError(
                        code: "NOT_LOADED",
                        message: "모델이 로드되지 않았습니다",
                        details: nil
                    ))
                    return
                }

                self.queue.async {
                    do {
                        let prompt = self.buildPrompt(text: text, sourceLang: sourceLang, targetLang: targetLang)
                        let response = try inference.generateResponse(inputText: prompt)
                        let cleaned = self.cleanResponse(response, targetLang: targetLang)

                        DispatchQueue.main.async { result(cleaned) }
                    } catch {
                        DispatchQueue.main.async {
                            result(FlutterError(
                                code: "TRANSLATE_FAILED",
                                message: "번역 실패: \(error.localizedDescription)",
                                details: nil
                            ))
                        }
                    }
                }

            case "isModelLoaded":
                result(self.llmInference != nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func findModelFile() -> String? {
        let fileManager = FileManager.default

        var searchDirs: [String] = []

        // App Documents directory
        if let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.path {
            searchDirs.append(docDir)
            searchDirs.append((docDir as NSString).appendingPathComponent("models"))
        }

        // App bundle
        if let bundlePath = Bundle.main.resourcePath {
            searchDirs.append(bundlePath)
        }

        // Check known model names
        for dir in searchDirs {
            for name in modelNames {
                let path = (dir as NSString).appendingPathComponent(name)
                if fileManager.fileExists(atPath: path) {
                    return path
                }
            }
        }

        // Scan documents for any .bin or .task file
        if let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.path {
            if let files = try? fileManager.contentsOfDirectory(atPath: docDir) {
                for file in files {
                    let ext = (file as NSString).pathExtension.lowercased()
                    if ext == "bin" || ext == "task" {
                        return (docDir as NSString).appendingPathComponent(file)
                    }
                }
            }
        }

        return nil
    }

    private func buildPrompt(text: String, sourceLang: String, targetLang: String) -> String {
        let sourceLabel = sourceLang == "Korean" ? "한국어" : "日本語"
        let targetLabel = targetLang == "Korean" ? "한국어" : "日本語"

        return """
        Translate the following \(sourceLabel) text to \(targetLabel). Output ONLY the translation, nothing else.

        \(sourceLabel): \(text)
        \(targetLabel):
        """
    }

    private func cleanResponse(_ response: String, targetLang: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["한국어:", "日本語:", "Korean:", "Japanese:", "Translation:"]
        for prefix in prefixes {
            if cleaned.lowercased().hasPrefix(prefix.lowercased()) {
                cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        if let firstLine = cleaned.components(separatedBy: .newlines).first(where: { !$0.isEmpty }) {
            cleaned = firstLine.trimmingCharacters(in: .whitespaces)
        }
        return cleaned
    }
}
