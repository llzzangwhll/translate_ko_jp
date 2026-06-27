package com.example.translate_ko_jp

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Message
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

    // LiteRT-LM engine. Unlike the older MediaPipe path, this runtime actually
    // accelerates .litertlm models (Gemma 4 E2B) on the GPU (OpenCL).
    private var engine: Engine? = null
    // Backend the loaded engine runs on: "gpu", "cpu", or "none". Surfaced to
    // Flutter for the on-screen diagnostic badge.
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

                            // Release any previous engine.
                            engine?.close()
                            engine = null
                            activeBackend = "none"

                            // Prefer the GPU backend (52 tok/s on Android for
                            // E2B). Fall back to CPU if GPU init fails on this
                            // device/driver.
                            engine = try {
                                val e = createEngine(modelPath, Backend.GPU())
                                activeBackend = "gpu"
                                e
                            } catch (e: Exception) {
                                Log.w(TAG, "GPU backend unavailable, falling back to CPU", e)
                                val e2 = createEngine(modelPath, Backend.CPU())
                                activeBackend = "cpu"
                                e2
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

                    val e = engine
                    if (e == null) {
                        result.error("NOT_LOADED", "모델이 로드되지 않았습니다", null)
                        return@setMethodCallHandler
                    }

                    executor.execute {
                        try {
                            val prompt = buildTranslationPrompt(text, sourceLang, targetLang)
                            Log.d(TAG, "Prompt: $prompt")

                            // Each translation is independent — use a fresh
                            // conversation so prior turns don't leak into it.
                            val raw = e.createConversation().use { conversation ->
                                messageText(conversation.sendMessage(prompt))
                            }
                            Log.d(TAG, "Raw response: $raw")
                            val cleaned = cleanResponse(raw, text)
                            Log.d(TAG, "Response: $cleaned")

                            mainHandler.post { result.success(cleaned) }
                        } catch (e2: Exception) {
                            Log.e(TAG, "Translation failed", e2)
                            mainHandler.post {
                                result.error("TRANSLATE_FAILED", "번역 실패: ${e2.message}", null)
                            }
                        }
                    }
                }

                "warmUp" -> {
                    val e = engine
                    if (e == null) {
                        result.error("NOT_LOADED", "모델이 로드되지 않았습니다", null)
                        return@setMethodCallHandler
                    }
                    executor.execute {
                        try {
                            // A tiny throwaway inference pays the one-time cost
                            // (GPU shader compile, KV-cache alloc) up front so
                            // the user's first real translation is fast.
                            e.createConversation().use { conversation ->
                                conversation.sendMessage("hi")
                            }
                            Log.i(TAG, "Warm-up inference done")
                            mainHandler.post { result.success(true) }
                        } catch (e2: Exception) {
                            Log.e(TAG, "Warm-up failed", e2)
                            mainHandler.post {
                                result.error("WARMUP_FAILED", "워밍업 실패: ${e2.message}", null)
                            }
                        }
                    }
                }

                "isModelLoaded" -> {
                    result.success(engine != null)
                }

                "activeBackend" -> {
                    result.success(if (engine != null) activeBackend else "none")
                }

                else -> result.notImplemented()
            }
        }
    }

    // A LiteRT-LM Message carries a list of Content parts; the model's reply is
    // in the Content.Text part(s). Concatenate them into a plain string.
    private fun messageText(message: Message): String =
        message.contents.contents
            .filterIsInstance<Content.Text>()
            .joinToString("") { it.text }

    private fun createEngine(modelPath: String, backend: Backend): Engine {
        val config = EngineConfig(
            modelPath = modelPath,
            backend = backend,
        )
        val engine = Engine(config)
        // Synchronous; can take several seconds. Always called on [executor].
        engine.initialize()
        return engine
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

        // Scan for any .litertlm/.task/.bin file in app directories
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

        // Plain instruction. LiteRT-LM's Conversation applies the model's chat
        // template itself, so we must NOT add <start_of_turn> markers here.
        return "Translate the following $source text into $target. " +
            "Translate every line in full. " +
            "Output only the $target translation — no explanations, no labels, " +
            "and do not repeat the original text.\n\n$text"
    }

    private fun cleanResponse(response: String, sourceText: String): String {
        var cleaned = response

        // Defensive: strip any special/turn tokens or angle-bracket tags that
        // might slip into the text.
        val markers = listOf("<end_of_turn>", "<start_of_turn>", "<turn/>", "<turn>", "<eos>")
        for (m in markers) {
            val idx = cleaned.indexOf(m)
            if (idx >= 0) cleaned = cleaned.substring(0, idx)
        }
        cleaned = cleaned.replace(Regex("<[^>]*>"), "")

        val prefixes = listOf("한국어:", "日本語:", "Korean:", "Japanese:", "Translation:", "번역:", "翻訳:")
        // Echo-filter per line so multi-line OCR input doesn't get its
        // translation thrown away. Each source line is matched individually.
        val sourceLines = sourceText.lines()
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .toSet()

        // Strip per-line labels and drop blank lines or lines that merely echo a
        // source line, then keep ALL remaining translation lines (not just the
        // first — OCR text is often several lines long).
        val picked = cleaned.lines()
            .map { line ->
                var l = line.trim()
                for (prefix in prefixes) {
                    if (l.startsWith(prefix, ignoreCase = true)) l = l.removePrefix(prefix).trim()
                }
                l
            }
            .filter { it.isNotBlank() && it !in sourceLines }

        return if (picked.isNotEmpty()) picked.joinToString("\n") else cleaned.trim()
    }

    override fun onDestroy() {
        engine?.close()
        engine = null
        executor.shutdown()
        super.onDestroy()
    }
}
