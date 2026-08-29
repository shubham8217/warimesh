package com.example.warimeshllmtest

import android.os.Bundle
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.ProgressListener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

// Minimal native test harness for the WariMesh on-device LLM: download the
// Gemma-3n E2B (.litertlm) model in-app (or load one pushed via adb), then
// chat with it — no Flutter, no platform channels, just MediaPipe
// tasks-genai directly.
class MainActivity : AppCompatActivity() {

    private val modelFile: File by lazy {
        File(File(filesDir, "llm"), MODEL_FILE)
    }

    private lateinit var statusText: TextView
    private lateinit var progressBar: ProgressBar
    private lateinit var progressText: TextView
    private lateinit var modelInfoText: TextView
    private lateinit var loadButton: Button
    private lateinit var downloadButton: Button
    private lateinit var chatScroll: ScrollView
    private lateinit var chatContainer: LinearLayout
    private lateinit var input: EditText
    private lateinit var sendButton: Button

    private var llm: LlmInference? = null
    private var downloading = false

    private val ui = CoroutineScope(Dispatchers.Main)
    private val inference = CoroutineScope(Dispatchers.Default)
    private val io = CoroutineScope(Dispatchers.IO)
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        buildUi()
        refreshModelInfo()
    }

    override fun onDestroy() {
        super.onDestroy()
        // Free the model (and its native memory) when the activity goes away.
        llm?.close()
        llm = null
    }

    // ---------------------------------------------------------------- UI

    private fun buildUi() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(16), dp(16), dp(16))
        }

        // Respect system bars (status bar top, gesture nav bar bottom) so
        // the input row and SEND button sit fully above the navigation
        // gesture area — otherwise taps near the bottom get swallowed by
        // the system gesture zone.
        ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or
                    WindowInsetsCompat.Type.ime()
            )
            v.setPadding(dp(16), dp(16) + bars.top, dp(16), dp(16) + bars.bottom)
            WindowInsetsCompat.CONSUMED
        }

        statusText = TextView(this).apply { this.text = "Checking model…"; textSize = 16f }
        root.addView(statusText)

        progressBar = ProgressBar(this).apply {
            visibility = View.GONE
            max = 100
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(8)
            ).apply { topMargin = dp(8) }
        }
        root.addView(progressBar)

        progressText = TextView(this).apply {
            visibility = View.GONE
            textSize = 12f
        }
        root.addView(progressText)

        val buttonRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(8) }
        }
        loadButton = Button(this).apply {
            text = "Load model"
            isEnabled = false
            setOnClickListener { loadModel() }
        }
        buttonRow.addView(loadButton, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        downloadButton = Button(this).apply {
            text = "Download model"
            isEnabled = false
            setOnClickListener { downloadModel() }
        }
        buttonRow.addView(downloadButton, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginStart = dp(8) })
        root.addView(buttonRow)

        modelInfoText = TextView(this).apply {
            textSize = 12f
            setPadding(0, dp(6), 0, dp(10))
        }
        root.addView(modelInfoText)

        chatScroll = ScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
            )
        }
        chatContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        chatScroll.addView(chatContainer)
        root.addView(chatScroll)

        val inputRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(10) }
        }
        input = EditText(this).apply {
            hint = "Ask something…"
            isEnabled = false
            imeOptions = EditorInfo.IME_ACTION_SEND
            setOnEditorActionListener { _, actionId, _ ->
                if (actionId == EditorInfo.IME_ACTION_SEND) {
                    sendMessage()
                    true
                } else false
            }
        }
        inputRow.addView(input, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

        sendButton = Button(this).apply {
            text = "Send"
            isEnabled = false
            setOnClickListener { sendMessage() }
        }
        inputRow.addView(sendButton, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { marginStart = dp(8) })

        root.addView(inputRow)
        setContentView(root)
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    // ----------------------------------------------------------- Model I/O

    private fun refreshModelInfo() {
        val file = modelFile
        if (file.exists()) {
            statusText.text = "Model downloaded — tap Load model"
            statusText.setTextColor(0xFFBA7517.toInt())
            modelInfoText.text = "${file.name}\n${file.length() / (1024 * 1024)} MB\n${file.absolutePath}"
            loadButton.isEnabled = true
            downloadButton.isEnabled = false
        } else {
            statusText.text = "Model not downloaded"
            statusText.setTextColor(0xFFCC4125.toInt())
            modelInfoText.text =
                "Tap Download model (3.7 GB, one time, needs internet). After that everything runs offline."
            loadButton.isEnabled = false
            downloadButton.isEnabled = !downloading
        }
    }

    private fun modelUrl(): String {
        // Escape hatch for mirrors / gated-repo tokens: write the URL to
        // files/llm/model_url.txt (via adb run-as) to override the default.
        val override = File(File(filesDir, "llm"), "model_url.txt")
        return if (override.exists()) {
            override.readText().trim().ifEmpty { MODEL_URL }
        } else {
            MODEL_URL
        }
    }

    private fun downloadModel() {
        if (downloading) return

        downloading = true
        downloadButton.isEnabled = false
        loadButton.isEnabled = false
        progressBar.visibility = View.VISIBLE
        progressBar.progress = 0
        progressText.visibility = View.VISIBLE
        progressText.text = "0%"
        statusText.text = "Downloading model… (3.7 GB, needs internet)"
        statusText.setTextColor(0xFFBA7517.toInt())

        io.launch {
            try {
                val part = File(modelFile.parentFile, "${modelFile.name}.part")
                modelFile.parentFile?.mkdirs()
                part.delete()

                // PRIMARY: the 4 chunked assets on this repo's GitHub
                // Release (part00..part03, concatenated). FALLBACK:
                // ModelScope single URL. Both verified by final size.
                var ok = downloadReleaseChunks(part)
                if (!ok) {
                    part.delete()
                    ok = downloadSingleUrl(FALLBACK_URL, part)
                }
                if (!ok || part.length() != MODEL_TOTAL_BYTES) {
                    part.delete()
                    throw IOException(
                        _downloadError ?: "Download incomplete — wrong size. Retry."
                    )
                }

                if (modelFile.exists()) modelFile.delete()
                part.renameTo(modelFile)

                withContext(Dispatchers.Main) {
                    downloading = false
                    progressBar.visibility = View.GONE
                    progressText.visibility = View.GONE
                    statusText.text = "Download complete — loading model…"
                    statusText.setTextColor(0xFF1D9E75.toInt())
                    refreshModelInfo()
                    // Download → Load → Run: as soon as the download
                    // finishes, load the model and unlock chat.
                    loadModel()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    downloading = false
                    progressBar.visibility = View.GONE
                    progressText.visibility = View.GONE
                    statusText.text = "Download failed: ${e.message}"
                    statusText.setTextColor(0xFFCC4125.toInt())
                    modelInfoText.text = "Fix the cause above, then tap Download model again."
                    downloadButton.isEnabled = true
                }
            }
        }
    }

    private var _downloadError: String? = null

    private fun newConnection(url: String): HttpURLConnection {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 20000
        conn.readTimeout = 30000
        conn.setRequestProperty("User-Agent", "WariMeshLlmTest/1.0")
        return conn
    }

    /// Downloads part00..part03 from the GitHub Release, appending to
    /// [dest]. Follows redirects manually (github.com → CDN).
    private fun downloadReleaseChunks(dest: File): Boolean {
        _downloadError = null
        val buf = ByteArray(64 * 1024)
        var written = 0L
        try {
            dest.outputStream().use { out ->
                for (i in 0 until MODEL_PARTS) {
                    val partName = "part%02d".format(i)
                    var url = "$RELEASE_BASE_URL/$partName"
                    var conn = newConnection(url)
                    conn.instanceFollowRedirects = false
                    // Follow up to 5 redirects (release assets redirect to
                    // objects.githubusercontent.com).
                    var code = -1
                    loop@ for (hop in 1..5) {
                        conn.connect()
                        code = conn.responseCode
                        if (code == HttpURLConnection.HTTP_MOVED_TEMP ||
                            code == HttpURLConnection.HTTP_MOVED_PERM ||
                            code == 307 || code == 308
                        ) {
                            url = conn.getHeaderField("Location") ?: break@loop
                            conn.disconnect()
                            conn = newConnection(url)
                            conn.instanceFollowRedirects = false
                        } else {
                            break@loop
                        }
                    }
                    if (code != HttpURLConnection.HTTP_OK) {
                        _downloadError = "GitHub chunk $partName: HTTP $code"
                        return false
                    }
                    val input = conn.inputStream
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        written += n
                        val pct = (written * 100 / MODEL_TOTAL_BYTES).toInt()
                        val p = pct.coerceAtMost(100)
                        mainHandler.post {
                            progressBar.progress = p
                            progressText.text = "$p%"
                        }
                    }
                    input.close()
                    conn.disconnect()
                }
            }
            return written == MODEL_TOTAL_BYTES
        } catch (e: Exception) {
            _downloadError = e.message
            return false
        }
    }

    private fun downloadSingleUrl(url: String, dest: File): Boolean {
        _downloadError = null
        val buf = ByteArray(64 * 1024)
        return try {
            var conn = newConnection(url)
            conn.instanceFollowRedirects = false
            var code = -1
            loop@ for (hop in 1..5) {
                conn.connect()
                code = conn.responseCode
                if (code == HttpURLConnection.HTTP_MOVED_TEMP ||
                    code == HttpURLConnection.HTTP_MOVED_PERM ||
                    code == 307 || code == 308
                ) {
                    val next = conn.getHeaderField("Location") ?: break@loop
                    conn.disconnect()
                    conn = newConnection(next)
                    conn.instanceFollowRedirects = false
                } else {
                    break@loop
                }
            }
            if (code != HttpURLConnection.HTTP_OK) {
                _downloadError = "Fallback HTTP $code"
                return false
            }
            val total = conn.contentLengthLong
            val input = conn.inputStream
            val out = dest.outputStream()
            var received = 0L
            var lastPct = -1
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                out.write(buf, 0, n)
                received += n
                if (total > 0) {
                    val pct = (received * 100 / total).toInt()
                    if (pct != lastPct) {
                        lastPct = pct
                        val p = pct
                        mainHandler.post {
                            progressBar.progress = p
                            progressText.text = "$p%"
                        }
                    }
                }
            }
            out.flush()
            out.close()
            input.close()
            conn.disconnect()
            true
        } catch (e: Exception) {
            _downloadError = e.message
            false
        }
    }

    private fun loadModel() {
        if (llm != null) {
            statusText.text = "Model already loaded"
            return
        }
        statusText.text = "Loading model… (first load can take a while)"
        statusText.setTextColor(0xFFBA7517.toInt())
        progressBar.visibility = View.VISIBLE
        progressBar.isIndeterminate = true
        inference.launch {
            try {
                val options = LlmInference.LlmInferenceOptions.builder()
                    .setModelPath(modelFile.absolutePath)
                    .setMaxTokens(512)
                    .setMaxTopK(40)
                    .build()
                val instance = LlmInference.createFromOptions(this@MainActivity, options)
                llm = instance
                withContext(Dispatchers.Main) {
                    progressBar.visibility = View.GONE
                    progressBar.isIndeterminate = false
                    statusText.text = "Model ready — ask away"
                    statusText.setTextColor(0xFF1D9E75.toInt())
                    input.isEnabled = true
                    sendButton.isEnabled = true
                    downloadButton.isEnabled = false
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    progressBar.visibility = View.GONE
                    progressBar.isIndeterminate = false
                    statusText.text = "Load failed: ${e.message}"
                    statusText.setTextColor(0xFFCC4125.toInt())
                }
            }
        }
    }

    // -------------------------------------------------------------- Chat

    private fun sendMessage() {
        val text = input.text.toString().trim()
        val model = llm
        if (text.isEmpty() || model == null) return
        input.setText("")
        appendChat("You", text)

        val loading = TextView(this).apply {
            this.text = "…"
            setPadding(0, dp(4), 0, dp(4))
        }
        chatContainer.addView(loading)
        scrollToBottom()

        inference.launch {
            try {
                val full = StringBuilder()
                // System prompt: turns the model into WariMesh's field
                // assistant for volunteers and warkaris. Preprended to every
                // question so emergency advice (snake bite, heat stroke,
                // dizziness…) is answered with immediate first-aid steps and
                // an "contact a healthcare worker" closing.
                val prompt = SYSTEM_PROMPT + "\n\n" + text
                // Streaming: ProgressListener fires with each partial result
                // (and done=true on the final one), exactly like the
                // LlmBridge.kt path in the Flutter app.
                model.generateResponseAsync(prompt, object : ProgressListener<String> {
                    override fun run(partial: String, done: Boolean) {
                        // The Gemma-3n bundle streams special tokens and
                        // repeated filler characters after the real answer
                        // (an emulator/CPU-backend quirk) — strip them so
                        // they never reach the chat UI.
                        var cleaned = partial
                            .replace("<end_of_turn>", "")
                            .replace("<start_of_turn>", "")
                            .replace("<eos>", "")
                            .replace("\u200D", "") // zero-width joiner
                            .replace("\u200B", "") // zero-width space
                            .replace("\uFE0F", "") // variation selector
                            .replace("\uD83E\uDD39", "") // 🦹 filler
                        // Collapse a run of one repeated non-letter
                        // character into a single occurrence — it's
                        // generation noise.
                        cleaned = cleaned.replace(Regex("(.)\\1{4,}"), "$1")
                        // Trim trailing whitespace-only runs.
                        cleaned = cleaned.trimEnd()
                        full.append(cleaned)
                        ui.launch {
                            loading.text = full.toString()
                            scrollToBottom()
                        }
                    }
                }).get()
            } catch (e: Exception) {
                ui.launch {
                    loading.text = "Error: ${e.message}"
                }
            }
        }
    }

    private fun appendChat(who: String, text: String) {
        chatContainer.addView(TextView(this).apply {
            this.text = "$who: $text"
            textSize = 16f
            setPadding(0, dp(8), 0, dp(4))
        })
        scrollToBottom()
    }

    private fun scrollToBottom() {
        chatScroll.post { chatScroll.fullScroll(View.FOCUS_DOWN) }
    }

    companion object {
        private const val MODEL_FILE = "gemma-3n-e2b-it-int4.litertlm"

        // PRIMARY download source: the 4 chunked assets on this repo's
        // GitHub Release (too big for a single git/GitHub file — 100 MB
        // cap — and LFS quota is 1 GB). FALLBACK: ModelScope mirror of the
        // official google/gemma-3n-E2B-it-litert-lm repo (no license gate).
        private const val RELEASE_BASE_URL =
            "https://github.com/RohitSwami33/Warimesh1/releases/download/gemma-3n-e2b-v1"
        private const val MODEL_PARTS = 4
        private const val MODEL_PART_BYTES = 913956864L // each chunk, exactly
        private const val MODEL_TOTAL_BYTES = 3655827456L // assembled size
        private const val FALLBACK_URL =
            "https://modelscope.cn/models/google/gemma-3n-E2B-it-litert-lm/resolve/master/gemma-3n-E2B-it-int4.litertlm"

        // System prompt: WariMesh's offline field assistant for volunteers
        // and warkaris (pilgrims). Emergency queries (snake bite, heat
        // stroke, dizziness, dehydration…) get immediate first-aid steps,
        // then "contact a healthcare worker ASAP". These are immediate
        // suggestions only, not a replacement for professional care.
        private const val SYSTEM_PROMPT = """You are the WariMesh assistant, an offline field companion on a phone at a walking pilgrimage (the Wari). You help VOLUNTEERS and WARKARIS (pilgrims) in emergencies when there is no mobile network and no healthcare worker nearby.

Your job:
- Answer queries about first aid and emergencies: snake bites, heat stroke, dehydration, dizziness, exhaustion, wounds, insect stings, and similar.
- Respond with the IMMEDIATE steps to take, in short numbered points.
- Always end with: contact a healthcare worker ASAP. These are only immediate first-aid suggestions, not professional medical advice.
- Keep answers short, calm, and practical. Use simple language.
- If asked anything unrelated to the pilgrimage/emergency context, briefly answer and steer back to safety.
- Never claim to be a doctor. Always remind that professional help is needed as soon as possible."""
    }
}
