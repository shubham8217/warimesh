// WariMesh — Kotlin side of the on-device LLM assistant (Gemma-3n E2B via
// the MediaPipe LLM Inference API, a.k.a. tasks-genai).
//
// The model file is far too large to ship inside the APK (~3.7 GB), so it
// lives in app-private storage (filesDir/llm/gemma-3n-e2b-it-int4.litertlm).
// Dart drives everything over a MethodChannel ("warimesh/llm") with events
// streamed back on the same channel's EventChannel.
package com.example.warimesh

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.ProgressListener
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class LlmBridge(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "warimesh/llm"
        const val EVENT_CHANNEL = "warimesh/llm/events"
        const val MODEL_DIR = "llm"
        const val MODEL_FILE = "gemma-3n-e2b-it-int4.litertlm"
        const val MAX_TOKENS = 512

        fun modelFile(context: Context): File =
            File(File(context.filesDir, MODEL_DIR), MODEL_FILE)
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = java.util.concurrent.Executors.newSingleThreadExecutor()

    @Volatile
    private var llm: LlmInference? = null

    private var eventSink: EventChannel.EventSink? = null

    fun register(methodChannel: MethodChannel, eventChannel: EventChannel) {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    fun dispose() {
        executor.execute {
            llm?.close()
            llm = null
        }
        executor.shutdown()
    }

    private fun emit(event: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(event) }
    }

    private fun emitError(code: String, message: String) {
        mainHandler.post { eventSink?.error(code, message, null) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getModelInfo" -> executor.execute {
                val file = modelFile(context)
                result.success(
                    mapOf(
                        "exists" to file.exists(),
                        "path" to file.absolutePath,
                        "sizeBytes" to (if (file.exists()) file.length() else 0L),
                    )
                )
            }

            "loadModel" -> executor.execute { loadModel(result) }
            "generate" -> executor.execute { generate(call, result) }
            "dispose" -> {
                executor.execute {
                    llm?.close()
                    llm = null
                    result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun loadModel(result: MethodChannel.Result) {
        try {
            if (llm != null) {
                result.success("already_loaded")
                return
            }
            val file = modelFile(context)
            if (!file.exists()) {
                result.error("model_missing", "Model file not found at ${file.absolutePath}", null)
                return
            }
            emit(mapOf("kind" to "loading"))

            // Backend choice is the single biggest factor in how fast this
            // feels. MediaPipe defaults to CPU, and a 4-bit ~5B-parameter
            // model decoded on a mid-range phone CPU runs at a few tokens a
            // second — slow enough to read as broken. The GPU backend is
            // several times faster, so try it first.
            //
            // GPU init genuinely does fail on some devices (driver quirks,
            // insufficient GPU memory), and when it does it throws rather
            // than degrading, so CPU stays as a fallback: slow beats not
            // working at all. Which one we ended up on is reported to Dart
            // so the UI can say so honestly instead of leaving someone
            // wondering why it crawls.
            var backendUsed = "gpu"
            llm = try {
                LlmInference.createFromOptions(
                    context,
                    LlmInference.LlmInferenceOptions.builder()
                        .setModelPath(file.absolutePath)
                        .setMaxTokens(MAX_TOKENS)
                        .setMaxTopK(40)
                        .setPreferredBackend(LlmInference.Backend.GPU)
                        .build()
                )
            } catch (gpuError: Throwable) {
                backendUsed = "cpu"
                emit(mapOf("kind" to "backend_fallback", "reason" to (gpuError.message ?: "GPU unavailable")))
                LlmInference.createFromOptions(
                    context,
                    LlmInference.LlmInferenceOptions.builder()
                        .setModelPath(file.absolutePath)
                        .setMaxTokens(MAX_TOKENS)
                        .setMaxTopK(40)
                        .setPreferredBackend(LlmInference.Backend.CPU)
                        .build()
                )
            }
            emit(mapOf("kind" to "loaded", "backend" to backendUsed))
            result.success("loaded")
        } catch (e: Exception) {
            result.error("load_failed", e.message ?: "Model load failed", null)
        }
    }

    private fun generate(call: MethodCall, result: MethodChannel.Result) {
        val prompt = call.argument<String>("prompt") ?: ""
        if (prompt.isBlank()) {
            result.error("empty_prompt", "Prompt is empty", null)
            return
        }
        val instance = llm
        if (instance == null) {
            result.error("not_loaded", "Model not loaded", null)
            return
        }
        val requestId = call.argument<String>("requestId") ?: ""
        try {
            instance.generateResponseAsync(
                prompt,
                ProgressListener { partial, done ->
                    mainHandler.post {
                        eventSink?.success(
                            mapOf(
                                "kind" to "token",
                                "requestId" to requestId,
                                "text" to partial,
                                "done" to done,
                            )
                        )
                        if (done) {
                            eventSink?.success(
                                mapOf("kind" to "done", "requestId" to requestId)
                            )
                        }
                    }
                }
            )
            result.success(true)
        } catch (e: Exception) {
            result.error("generate_failed", e.message ?: "Generation failed", null)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
