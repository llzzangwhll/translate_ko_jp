package com.example.translate_ko_jp

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.example.translate_ko_jp/gemma"
        private const val TAG = "GemmaTranslator"
        private val MODEL_EXTENSIONS = listOf("litertlm", "task", "bin")
        private val MODEL_NAMES = listOf(
            "gemma-4-E2B-it.litertlm",
            "gemma-4-E2B-it-web.task",
            "gemma3-1B-it-int4.task",
            "gemma-2b-it-gpu-int4.bin",
            "gemma-2b-it-cpu-int4.bin",
            "gemma3-1b-it-int4.bin",
            "model.litertlm",
            "model.bin",
            "model.task"
        )
    }

    private var llmInference: LlmInference? = null
    // Which backend the loaded engine is actually running on: "gpu", "cpu",
    // or "none" when nothing is loaded. Surfaced to Flutter for diagnostics.
    @Volatile private var activeBackend: String = "none"
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkModelExists" -> {
                    val path = findModelFile()
                    result.success(path != null)
                }

                "loadModel" -> {
                    executor.execute {
                        try {
                            // Use explicit path if provided, otherwise auto-detect
                            val modelPath = call.argument<String>("modelPath") ?: findModelFile()

                            if (modelPath == null) {
                                mainHandler.post {
                                    result.error("MODEL_NOT_FOUND",
                                        "모델 파일을 찾을 수 없습니다.",
                                        null)
                                }
                                return@execute
                            }

                            val file = File(modelPath)
                            if (!file.exists() || file.length() == 0L) {
                                mainHandler.post {
                                    result.error("MODEL_NOT_FOUND",
                                        "모델 파일이 존재하지 않거나 비어있습니다: $modelPath",
                                        null)
                                }
                                return@execute
                            }

                            Log.i(TAG, "Loading model from: $modelPath (${file.length() / 1024 / 1024}MB)")

                            // Close previous instance if any
                            llmInference?.close()

                            // Prefer the GPU backend (much faster than CPU for a
                            // 2B+ model). Some .litertlm builds are CPU-only, so
                            // fall back to CPU if GPU initialization fails.
                            llmInference = try {
                                val engine = createEngine(modelPath, LlmInference.Backend.GPU)
                                activeBackend = "gpu"
                                engine
                            } catch (e: Exception) {
                                Log.w(TAG, "GPU backend unavailable, falling back to CPU", e)
                                val engine = createEngine(modelPath, LlmInference.Backend.CPU)
                                activeBackend = "cpu"
                                engine
                            }
                            Log.i(TAG, "Model loaded successfully on backend=$activeBackend")
                            mainHandler.post { result.success(true) }
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to load model", e)
                            mainHandler.post {
                                result.error("LOAD_FAILED", "모델 로딩 실패: ${e.message}", null)
                            }
                        }
                    }
                }

                "translate" -> {
                    val text = call.argument<String>("text") ?: ""
                    val sourceLang = call.argument<String>("sourceLang") ?: "Korean"
                    val targetLang = call.argument<String>("targetLang") ?: "Japanese"

                    if (llmInference == null) {
                        result.error("NOT_LOADED", "모델이 로드되지 않았습니다", null)
                        return@setMethodCallHandler
                    }

                    executor.execute {
                        try {
                            val prompt = buildTranslationPrompt(text, sourceLang, targetLang)
                            Log.d(TAG, "Prompt: $prompt")

                            val response = llmInference!!.generateResponse(prompt)
                            Log.d(TAG, "Raw response: $response")
                            val cleaned = cleanResponse(response, text)
                            Log.d(TAG, "Response: $cleaned")

                            mainHandler.post { result.success(cleaned) }
                        } catch (e: Exception) {
                            Log.e(TAG, "Translation failed", e)
                            mainHandler.post {
                                result.error("TRANSLATE_FAILED", "번역 실패: ${e.message}", null)
                            }
                        }
                    }
                }

                "warmUp" -> {
                    if (llmInference == null) {
                        result.error("NOT_LOADED", "모델이 로드되지 않았습니다", null)
                        return@setMethodCallHandler
                    }
                    executor.execute {
                        try {
                            // A tiny throwaway inference pays the one-time cost
                            // (graph build, GPU shader compile, KV-cache alloc)
                            // so the user's first real translation is fast.
                            llmInference!!.generateResponse("hi")
                            Log.i(TAG, "Warm-up inference done")
                            mainHandler.post { result.success(true) }
                        } catch (e: Exception) {
                            Log.e(TAG, "Warm-up failed", e)
                            mainHandler.post {
                                result.error("WARMUP_FAILED", "워밍업 실패: ${e.message}", null)
                            }
                        }
                    }
                }

                "isModelLoaded" -> {
                    result.success(llmInference != null)
                }

                "activeBackend" -> {
                    result.success(if (llmInference != null) activeBackend else "none")
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun createEngine(modelPath: String, backend: LlmInference.Backend): LlmInference {
        val options = LlmInference.LlmInferenceOptions.builder()
            .setModelPath(modelPath)
            .setMaxTokens(512)
            .setPreferredBackend(backend)
            .build()
        return LlmInference.createFromOptions(applicationContext, options)
    }

    private fun findModelFile(): String? {
        val searchDirs = listOf(
            filesDir,
            File(filesDir, "models"),
            getExternalFilesDir(null),
            File("/sdcard/Download"),
            File("/sdcard/Documents"),
        ).filterNotNull()

        // Check known model names first
        for (dir in searchDirs) {
            for (name in MODEL_NAMES) {
                val file = File(dir, name)
                if (file.exists() && file.length() > 0) {
                    return file.absolutePath
                }
            }
        }

        // Scan for any .bin or .task file in app directories
        val appDirs = listOf(filesDir, File(filesDir, "models"), getExternalFilesDir(null)).filterNotNull()
        for (dir in appDirs) {
            if (dir.exists()) {
                dir.listFiles()?.firstOrNull {
                    it.extension in MODEL_EXTENSIONS && it.length() > 0
                }?.let { return it.absolutePath }
            }
        }

        // Also check app_flutter directory (used by path_provider)
        val flutterDir = File(filesDir.parentFile, "app_flutter")
        if (flutterDir.exists()) {
            flutterDir.listFiles()?.firstOrNull {
                it.extension in MODEL_EXTENSIONS && it.length() > 0
            }?.let { return it.absolutePath }
        }

        return null
    }

    private fun buildTranslationPrompt(text: String, sourceLang: String, targetLang: String): String {
        val source = if (sourceLang == "Korean") "Korean" else "Japanese"
        val target = if (targetLang == "Korean") "Korean" else "Japanese"

        // Plain instruction with the source sentence given directly (no
        // "Korean:/Japanese:" scaffolding, which the model tends to echo back).
        val instruction =
            "Translate the following $source sentence into $target. " +
            "Output only the $target translation — no explanations, no labels, " +
            "and do not repeat the original sentence.\n\n$text"

        // Gemma instruction-tuned chat template. Wrapping the request in
        // <start_of_turn>/<end_of_turn> lets the engine recognize the turn
        // boundary and stop generating, instead of spilling turn tokens.
        return "<start_of_turn>user\n$instruction<end_of_turn>\n<start_of_turn>model\n"
    }

    private fun cleanResponse(response: String, sourceText: String): String {
        var cleaned = response

        // The model can emit special/turn tokens (e.g. <end_of_turn>, <turn/>,
        // <eos>). Cut everything from the first such marker, then strip any
        // remaining angle-bracket tags so they never reach the UI.
        val markers = listOf("<end_of_turn>", "<start_of_turn>", "<turn/>", "<turn>", "<eos>")
        for (m in markers) {
            val idx = cleaned.indexOf(m)
            if (idx >= 0) cleaned = cleaned.substring(0, idx)
        }
        cleaned = cleaned.replace(Regex("<[^>]*>"), "")

        val prefixes = listOf("한국어:", "日本語:", "Korean:", "Japanese:", "Translation:", "번역:", "翻訳:")
        val src = sourceText.trim()

        // Strip per-line labels and drop blank lines or lines that merely echo
        // the source sentence, then take the first real translation line.
        val pick = cleaned.lines()
            .map { line ->
                var l = line.trim()
                for (prefix in prefixes) {
                    if (l.startsWith(prefix, ignoreCase = true)) l = l.removePrefix(prefix).trim()
                }
                l
            }
            .firstOrNull { it.isNotBlank() && it != src }

        return pick ?: cleaned.trim()
    }

    override fun onDestroy() {
        llmInference?.close()
        executor.shutdown()
        super.onDestroy()
    }
}
