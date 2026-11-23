package com.example.media_downloader

import android.content.Context
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Envoltorio de youtubedl-android: inicialización, actualización de yt-dlp,
 * análisis de URLs y traducción de las líneas de progreso de yt-dlp.
 *
 * La librería ya agrega por su cuenta `--js-runtimes quickjs:<ruta>` y `--ffmpeg-location`.
 */
object YtDlpEngine {
    private const val PREFS = "engine_prefs"
    private const val KEY_LAST_UPDATE = "ytdlp_last_update_ms"
    private const val UPDATE_INTERVAL_MS = 24L * 60 * 60 * 1000

    private val initLock = Any()

    @Volatile
    private var initialized = false

    /** Evita ejecutar yt-dlp mientras su binario se está reemplazando. */
    private val updateMutex = Mutex()

    private val speedRegex = Regex("""at\s+~?\s*([\d.]+\s*[KMGT]?i?B/s)""")

    /** Líneas de `-v` que identifican versión de yt-dlp, Python y runtimes JS. */
    private val diagnosticKeys = listOf("version", "JS runtimes", "Optional libraries", "exe versions")

    fun ensureInitialized(context: Context) {
        if (initialized) return
        synchronized(initLock) {
            if (initialized) return
            YoutubeDL.getInstance().init(context.applicationContext)
            FFmpeg.getInstance().init(context.applicationContext)
            initialized = true
        }
    }

    /**
     * Actualiza yt-dlp (canal estable) si han pasado 24 h desde la última actualización
     * exitosa, o siempre si [force]. Devuelve el estado como texto.
     */
    suspend fun updateIfDue(context: Context, force: Boolean = false): String {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        if (!force && now - prefs.getLong(KEY_LAST_UPDATE, 0L) < UPDATE_INTERVAL_MS) {
            return "SKIPPED"
        }
        return updateMutex.withLock {
            ensureInitialized(context)
            val status = YoutubeDL.getInstance().updateYoutubeDL(context.applicationContext)
            prefs.edit().putLong(KEY_LAST_UPDATE, now).apply()
            status?.name ?: "OK"
        }
    }

    /** Espera a que termine una actualización en curso (si la hay). */
    suspend fun awaitPendingUpdate() {
        updateMutex.withLock { }
    }

    fun version(context: Context): String? = YoutubeDL.getInstance().version(context.applicationContext)

    data class AnalyzeResult(val json: String, val debug: List<String>, val warnings: List<String>)

    suspend fun analyze(context: Context, url: String): AnalyzeResult {
        ensureInitialized(context)
        awaitPendingUpdate()
        val request = YoutubeDLRequest(url).apply {
            addOption("--dump-json")
            addOption("--no-playlist")
            addOption("-v")
        }
        val response = YoutubeDL.getInstance().execute(request)
        val errLines = response.err.lines()
        val debug = errLines
            .filter { line -> line.startsWith("[debug] ") && diagnosticKeys.any { line.contains(it) } }
            .take(12)
        val warnings = errLines.filter { it.startsWith("WARNING:") }
        return AnalyzeResult(response.out, debug, warnings)
    }

    /** Quita las líneas `[debug]` de los mensajes de error para no ensuciar la UI. */
    fun cleanError(message: String?): String {
        val cleaned = message
            ?.lines()
            ?.filterNot { it.startsWith("[debug]") || it.isBlank() }
            ?.joinToString("\n")
            ?.trim()
        return if (cleaned.isNullOrEmpty()) "Error desconocido durante la operación" else cleaned
    }

    /**
     * Traduce una línea de salida de yt-dlp a un evento de progreso para Flutter.
     * Devuelve null si la línea no aporta información de progreso.
     */
    fun describeProgress(progress: Float, etaSeconds: Long, line: String): Map<String, Any?>? {
        return when {
            line.startsWith("[Merger]") -> processing("Uniendo pistas de audio y video…")
            line.startsWith("[ExtractAudio]") -> processing("Convirtiendo audio…")
            line.startsWith("[Fixup") || line.startsWith("[VideoRemuxer]") || line.startsWith("[VideoConvertor]") ->
                processing("Ajustando contenedor…")
            line.startsWith("[download]") && line.contains('%') -> mapOf(
                "status" to "downloading",
                "progress" to progress.toDouble().coerceIn(0.0, 100.0),
                "speed" to speedRegex.find(line)?.groupValues?.get(1)?.replace(" ", ""),
                "eta" to formatEta(etaSeconds),
                "step" to "Descargando flujo de medios…",
            )
            else -> null
        }
    }

    private fun processing(step: String) = mapOf(
        "status" to "processing",
        "progress" to 99.0,
        "step" to step,
    )

    private fun formatEta(seconds: Long): String? {
        if (seconds < 0) return null
        val h = seconds / 3600
        val m = (seconds % 3600) / 60
        val s = seconds % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
    }
}
