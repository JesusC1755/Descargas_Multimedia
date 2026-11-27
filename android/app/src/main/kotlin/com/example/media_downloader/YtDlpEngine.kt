package com.example.media_downloader

import android.content.Context
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/**
 * Envoltorio de youtubedl-android: inicialización, actualización de yt-dlp,
 * análisis de URLs y traducción de las líneas de progreso de yt-dlp.
 *
 * La librería agrega por su cuenta `--js-runtimes quickjs:<ruta>`. El APK no incluye FFmpeg:
 * las pistas se unen y el audio se convierte con [MediaTools].
 */
object YtDlpEngine {
    private const val PREFS = "engine_prefs"
    private const val KEY_LAST_UPDATE = "ytdlp_last_update_ms"
    private const val UPDATE_INTERVAL_MS = 24L * 60 * 60 * 1000

    /**
     * Vigencia del JSON de análisis reutilizado al descargar. Los enlaces de YouTube
     * caducan a las ~6 h; 3 h deja margen.
     */
    private const val INFO_TTL_MS = 3L * 60 * 60 * 1000

    private val initLock = Any()

    @Volatile
    private var initialized = false

    /** Evita ejecutar yt-dlp mientras su binario se está reemplazando. */
    private val updateMutex = Mutex()

    private val speedRegex = Regex("""at\s+~?\s*([\d.]+\s*[KMGT]?i?B/s)""")

    /** Líneas de `-v` que identifican versión de yt-dlp, Python y runtimes JS. */
    fun ensureInitialized(context: Context) {
        if (initialized) return
        synchronized(initLock) {
            if (initialized) return
            YoutubeDL.getInstance().init(context.applicationContext)
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

    data class AnalyzeResult(val json: String, val warnings: List<String>)

    /** Fuerza clientes de YouTube (`youtube:player_client=…`); null = los de yt-dlp por defecto. */
    fun applyPlayerClient(request: YoutubeDLRequest, playerClient: String?) {
        if (!playerClient.isNullOrBlank()) {
            request.addOption("--extractor-args", "youtube:player_client=$playerClient")
        }
    }

    /** YouTube sin yt-dlp ([YouTubeFastExtractor]); null si la URL no es de YouTube. */
    fun analyzeFast(context: Context, url: String): AnalyzeResult? {
        val videoId = YouTubeFastExtractor.videoIdOf(url) ?: return null
        val json = YouTubeFastExtractor.analyze(videoId)
        saveInfo(context, url, json)
        return AnalyzeResult(json, emptyList())
    }

    suspend fun analyze(context: Context, url: String, playerClient: String? = null): AnalyzeResult {
        ensureInitialized(context)
        awaitPendingUpdate()
        val request = YoutubeDLRequest(url).apply {
            addOption("--dump-json")
            addOption("--no-playlist")
            applyPlayerClient(this, playerClient)
        }
        val response = YoutubeDL.getInstance().execute(request)
        val warnings = response.err.lines().filter { it.startsWith("WARNING:") }
        saveInfo(context, url, response.out)
        return AnalyzeResult(response.out, warnings)
    }

    // --- Caché del análisis -------------------------------------------------------------
    // La descarga reutiliza el JSON del análisis con `--load-info-json`: así no se repite
    // la extracción (arranque de Python + desafío JS de YouTube con QuickJS, ~35 s).

    private fun infoDir(context: Context) = File(context.cacheDir, "info")

    private fun infoFileFor(context: Context, url: String): File {
        val hash = MessageDigest.getInstance("SHA-256").digest(url.toByteArray())
            .joinToString("") { "%02x".format(it) }
            .take(32)
        return File(infoDir(context), "$hash.json")
    }

    private fun saveInfo(context: Context, url: String, json: String) {
        val line = json.lineSequence().firstOrNull { it.startsWith("{") } ?: return
        try {
            val target = infoFileFor(context, url)
            target.parentFile?.mkdirs()
            val tmp = File(target.parentFile, target.name + ".tmp")
            tmp.writeText(line)
            if (!tmp.renameTo(target)) tmp.delete()
        } catch (_: Exception) {
            // Sin caché la descarga simplemente vuelve a extraer desde la URL.
        }
    }

    /** JSON de análisis vigente para [url], o null si no existe o caducó. */
    fun cachedInfoFor(context: Context, url: String): File? {
        val file = infoFileFor(context, url)
        return file.takeIf { it.isFile && System.currentTimeMillis() - it.lastModified() < INFO_TTL_MS }
    }

    /** El análisis guardado si lo hizo [YouTubeFastExtractor] (se descarga sin yt-dlp); si no, null. */
    fun fastInfoOf(file: File): JSONObject? = try {
        JSONObject(file.readText()).takeIf { it.optString("_engine") == YouTubeFastExtractor.ENGINE }
    } catch (_: Exception) {
        null
    }

    fun discardInfo(context: Context, url: String) {
        infoFileFor(context, url).delete()
    }

    fun cleanExpiredInfo(context: Context) {
        val now = System.currentTimeMillis()
        infoDir(context).listFiles()?.forEach { if (now - it.lastModified() >= INFO_TTL_MS) it.delete() }
    }

    /** Quita las líneas vacías de los mensajes de error para mostrarlos en la UI. */
    fun cleanError(message: String?): String {
        val cleaned = message
            ?.lines()
            ?.filterNot { it.isBlank() }
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
            line.startsWith("[download]") && line.contains('%') -> downloading(
                progress.toDouble(),
                speedRegex.find(line)?.groupValues?.get(1)?.replace(" ", ""),
                etaSeconds,
            )
            else -> null
        }
    }

    fun downloading(progress: Double, speed: String?, etaSeconds: Long) = mapOf(
        "status" to "downloading",
        "progress" to progress.coerceIn(0.0, 100.0),
        "speed" to speed,
        "eta" to formatEta(etaSeconds),
        "step" to "Descargando flujo de medios…",
    )

    /** Velocidad con el mismo formato que yt-dlp (`8.52MiB/s`). */
    fun formatSpeed(bytesPerSecond: Double): String? = when {
        bytesPerSecond <= 0 -> null
        bytesPerSecond >= 1024 * 1024 -> "%.2fMiB/s".format(java.util.Locale.US, bytesPerSecond / (1024 * 1024))
        else -> "%.2fKiB/s".format(java.util.Locale.US, bytesPerSecond / 1024)
    }

    fun processing(step: String) = mapOf(
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
