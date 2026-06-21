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

                            val options = LlmInference.LlmInferenceOptions.builder()
                                .setModelPath(modelPath)
                                .setMaxTokens(512)
                                .build()

                            llmInference = LlmInference.createFromOptions(applicationContext, options)
                            Log.i(TAG, "Model loaded successfully")

                            // Warm up while the splash is still showing: a tiny
                            // throwaway inference pays the one-time cost (graph
                            // build, GPU shader compile, KV-cache alloc) up front
                            // so the user's first real translation is fast.
                            // Non-fatal: a failure here must not block loading.
                            try {
                                llmInference!!.generateResponse("hi")
                                Log.i(TAG, "Warm-up inference done")
                            } catch (e: Exception) {
                                Log.w(TAG, "Warm-up inference failed (non-fatal)", e)
                            }

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
                            val cleaned = cleanResponse(response, targetLang)
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

                "isModelLoaded" -> {
                    result.success(llmInference != null)
                }

                else -> result.notImplemented()
            }
        }
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
        val sourceLabel = if (sourceLang == "Korean") "한국어" else "日本語"
        val targetLabel = if (targetLang == "Korean") "한국어" else "日本語"

        return """Translate the following $sourceLabel text to $targetLabel. Output ONLY the translation, nothing else.

$sourceLabel: $text
$targetLabel:"""
    }

    private fun cleanResponse(response: String, targetLang: String): String {
        var cleaned = response.trim()
        val prefixes = listOf("한국어:", "日本語:", "Korean:", "Japanese:", "Translation:")
        for (prefix in prefixes) {
            if (cleaned.startsWith(prefix, ignoreCase = true)) {
                cleaned = cleaned.removePrefix(prefix).trim()
            }
        }
        // Take only the first meaningful line
        cleaned = cleaned.lines().firstOrNull { it.isNotBlank() }?.trim() ?: cleaned
        return cleaned
    }

    override fun onDestroy() {
        llmInference?.close()
        executor.shutdown()
        super.onDestroy()
    }
}
