package com.example.media_downloader

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.File
import java.io.IOException

private const val TAG = "MediaDownloader"

/**
 * Servicio en primer plano que ejecuta la descarga: sigue funcionando si el usuario cambia
 * de app o apaga la pantalla, muestra el progreso en una notificación con botón "Cancelar"
 * y publica cada evento en [DownloadStateHolder] para que Flutter lo reciba.
 */
class DownloadService : Service() {

    data class Params(
        val id: String,
        val url: String,
        val baseName: String,
        val format: String,
        val height: Int,
        val isAudioOnly: Boolean,
        val audioFormat: String,
        val treeUri: String?,
        val playerClient: String?,
    )

    companion object {
        private const val ACTION_START = "com.example.media_downloader.action.START"
        private const val ACTION_CANCEL = "com.example.media_downloader.action.CANCEL"

        private const val CHANNEL_PROGRESS = "downloads_progress"
        private const val CHANNEL_RESULT = "downloads_result"
        private const val NOTIFICATION_PROGRESS = 4100
        private const val NOTIFICATION_RESULT = 4101
        private const val WAKE_LOCK_TIMEOUT_MS = 3L * 60 * 60 * 1000
        private const val NOTIFY_INTERVAL_MS = 700L
        private const val BRAND_COLOR = 0xFFA855F7.toInt()

        /** Carpeta privada donde yt-dlp escribe antes de exportar al destino final. */
        fun workRoot(context: Context) = File(context.cacheDir, "downloads")

        fun start(context: Context, p: Params) {
            val intent = Intent(context, DownloadService::class.java).apply {
                action = ACTION_START
                putExtra("id", p.id)
                putExtra("url", p.url)
                putExtra("baseName", p.baseName)
                putExtra("format", p.format)
                putExtra("height", p.height)
                putExtra("isAudioOnly", p.isAudioOnly)
                putExtra("audioFormat", p.audioFormat)
                putExtra("treeUri", p.treeUri)
                putExtra("playerClient", p.playerClient)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun cancel(context: Context) {
            context.startService(Intent(context, DownloadService::class.java).setAction(ACTION_CANCEL))
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var current: Params? = null

    @Volatile
    private var cancelRequested = false

    @Volatile
    private var timeoutReached = false
    private var wakeLock: PowerManager.WakeLock? = null
    private var lastNotifyAt = 0L
    private var lastStatus: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> handleStart(intent)
            ACTION_CANCEL -> requestCancel()
            else -> if (current == null) stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun handleStart(intent: Intent) {
        val params = Params(
            id = intent.getStringExtra("id") ?: return stopSelf(),
            url = intent.getStringExtra("url") ?: return stopSelf(),
            baseName = intent.getStringExtra("baseName") ?: "video",
            format = intent.getStringExtra("format") ?: "",
            height = intent.getIntExtra("height", 0),
            isAudioOnly = intent.getBooleanExtra("isAudioOnly", false),
            audioFormat = intent.getStringExtra("audioFormat") ?: "mp3",
            treeUri = intent.getStringExtra("treeUri"),
            playerClient = intent.getStringExtra("playerClient"),
        )

        createChannels()
        // Debe llamarse en los primeros segundos tras startForegroundService.
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_PROGRESS,
            buildProgressNotification(params.baseName, null),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0,
        )

        if (current != null) {
            Log.w(TAG, "Ya hay una descarga en curso; se ignora ${params.id}")
            return
        }
        current = params
        cancelRequested = false
        timeoutReached = false
        acquireWakeLock()

        scope.launch {
            try {
                runDownload(params)
            } finally {
                releaseWakeLock()
                current = null
                ServiceCompat.stopForeground(this@DownloadService, ServiceCompat.STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
    }

    private suspend fun runDownload(p: Params) {
        val workDir = File(workRoot(this), p.id).apply { mkdirs() }
        try {
            val cachedInfo = YtDlpEngine.cachedInfoFor(applicationContext, p.url)
            val fastInfo = cachedInfo?.let { YtDlpEngine.fastInfoOf(it) }
            val output = if (fastInfo == null) {
                downloadWithYtDlp(p, workDir, cachedInfo)
            } else {
                try {
                    downloadDirect(p, fastInfo, workDir)
                } catch (e: YoutubeDL.CanceledException) {
                    throw e
                } catch (e: Exception) {
                    if (cancelRequested) throw YoutubeDL.CanceledException()
                    // URL caducada u otro fallo: yt-dlp desde la URL.
                    Log.w(TAG, "Descarga directa falló; reintentando con yt-dlp: ${e.message?.take(300)}")
                    YtDlpEngine.discardInfo(applicationContext, p.url)
                    workDir.listFiles()?.forEach { it.deleteRecursively() }
                    emit(p, mapOf("status" to "downloading", "progress" to 0.0, "step" to "Reintentando descarga…"))
                    downloadWithYtDlp(p, workDir, null)
                }
            }
            if (cancelRequested) throw YoutubeDL.CanceledException()

            emit(p, mapOf("status" to "processing", "progress" to 99.0, "step" to "Guardando en la carpeta de destino…"))
            val exported = MediaExporter.export(applicationContext, output, p.treeUri)
            Log.i(TAG, "Archivo exportado: ${exported.displayPath} (${exported.uri})")

            emit(
                p,
                mapOf(
                    "status" to "completed",
                    "progress" to 100.0,
                    "filePath" to exported.displayPath,
                    "uri" to exported.uri.toString(),
                    "step" to "¡Descarga Exitosa!",
                )
            )
        } catch (e: Throwable) {
            if (timeoutReached) {
                emit(p, mapOf("status" to "error", "error" to "Android detuvo la descarga por superar el tiempo máximo en segundo plano."))
            } else if (cancelRequested || e is YoutubeDL.CanceledException) {
                emit(p, mapOf("status" to "cancelled", "step" to "Descarga cancelada"))
            } else {
                Log.w(TAG, "Descarga fallida", e)
                emit(p, mapOf("status" to "error", "error" to YtDlpEngine.cleanError(e.message)))
            }
        } finally {
            workDir.deleteRecursively()
        }
    }

    private val isCancelled: () -> Boolean = { cancelRequested }

    /** YouTube con el análisis de [YouTubeFastExtractor]: HTTP directo y unión con MediaMuxer. */
    private suspend fun downloadDirect(p: Params, info: JSONObject, workDir: File): File {
        val formats = info.getJSONArray("formats").let { list -> (0 until list.length()).map { list.getJSONObject(it) } }
        val audio = formats
            .filter { it.optString("vcodec") == "none" && it.optString("acodec").startsWith("mp4a") }
            .sortedWith(
                compareByDescending<JSONObject> { it.optBoolean("audio_is_default", true) }
                    .thenByDescending { it.optDouble("tbr", 0.0) }
            )
            .firstOrNull() ?: throw IOException("Sin pista de audio AAC")

        val partsDir = File(workDir, "parts")
        val audioPart = DirectDownloader.Part(audio.getString("url"), File(partsDir, "audio.m4a"), audio.optLong("filesize"))
        var videoPart: DirectDownloader.Part? = null
        if (!p.isAudioOnly) {
            // Resolución "estándar" = lado menor (1080 en 1920x1080 y en 1080x1920), como en Dart.
            fun res(f: JSONObject) = minOf(f.optInt("width"), f.optInt("height"))
            val videos = formats.filter { it.optString("vcodec").startsWith("avc1") && it.optString("acodec") == "none" }
            val target = if (p.height > 0) p.height else 1080
            val video = videos.filter { res(it) <= target }
                .maxWithOrNull(compareBy<JSONObject>({ res(it) }, { it.optDouble("tbr", 0.0) }))
                ?: videos.minByOrNull { res(it) }
                ?: throw IOException("Sin pista de vídeo H.264")
            videoPart = DirectDownloader.Part(video.getString("url"), File(partsDir, "video.mp4"), video.optLong("filesize"))
        }

        val started = System.currentTimeMillis()
        DirectDownloader(YouTubeFastExtractor.USER_AGENT, isCancelled)
            .download(listOfNotNull(videoPart, audioPart)) { progress ->
                val percent = if (progress.total > 0) progress.downloaded * 100.0 / progress.total else 0.0
                val eta = if (progress.total > 0 && progress.bytesPerSecond > 0) {
                    ((progress.total - progress.downloaded) / progress.bytesPerSecond).toLong()
                } else {
                    -1L
                }
                emit(p, YtDlpEngine.downloading(percent, YtDlpEngine.formatSpeed(progress.bytesPerSecond), eta))
            }
        Log.i(TAG, "Descarga directa: ${System.currentTimeMillis() - started} ms")

        return if (videoPart == null) {
            emit(p, YtDlpEngine.processing("Convirtiendo audio…"))
            MediaTools.convertAudio(audioPart.dest, workDir, p.baseName, p.audioFormat, isCancelled)
        } else {
            emit(p, YtDlpEngine.processing("Uniendo pistas de audio y video…"))
            MediaTools.mux(listOf(videoPart.dest, audioPart.dest), workDir, p.baseName, isCancelled)
        }
    }

    /**
     * Cualquier sitio con yt-dlp. Sin FFmpeg, yt-dlp deja vídeo y audio en archivos separados
     * (`.f<id>.<ext>`) y aquí se unen o se convierte el audio con [MediaTools].
     */
    private suspend fun downloadWithYtDlp(p: Params, workDir: File, cachedInfo: File?): File {
        YtDlpEngine.ensureInitialized(applicationContext)
        YtDlpEngine.awaitPendingUpdate()
        if (cancelRequested) throw YoutubeDL.CanceledException()
        val rawDir = File(workDir, "raw").apply { mkdirs() }

        fun buildRequest(info: File?, client: String?): YoutubeDLRequest {
            // Con el JSON del análisis no se repite la extracción (ni el desafío JS de YouTube).
            val request = if (info != null) {
                YoutubeDLRequest(emptyList<String>()).addOption("--load-info-json", info.absolutePath)
            } else {
                YoutubeDLRequest(p.url).addOption("--no-playlist").also {
                    YtDlpEngine.applyPlayerClient(it, client)
                }
            }
            return request.apply {
                addOption("-o", File(rawDir, "${p.baseName}.%(ext)s").absolutePath)
                addOption("--newline")
                addOption("--fixup", "never")
                if (p.format.isNotEmpty()) addOption("-f", p.format)
                if (!p.isAudioOnly) {
                    // `proto`: a igual resolución, HTTPS antes que HLS (m3u8 baja en fragmentos).
                    addOption("-S", "vcodec:h264,res,proto,acodec:aac")
                }
            }
        }

        fun run(info: File?, client: String?) {
            val started = System.currentTimeMillis()
            YoutubeDL.getInstance().execute(buildRequest(info, client), p.id) { progress: Float, eta: Long, line: String ->
                YtDlpEngine.describeProgress(progress, eta, line)?.let { emit(p, it) }
            }
            val mode = if (info != null) "info-json" else "url"
            Log.i(TAG, "Descarga yt-dlp ($mode): ${System.currentTimeMillis() - started} ms")
        }

        if (cachedInfo == null) {
            run(null, p.playerClient)
        } else {
            try {
                run(cachedInfo, null)
            } catch (e: YoutubeDL.CanceledException) {
                throw e
            } catch (e: Exception) {
                if (cancelRequested) throw YoutubeDL.CanceledException()
                // Enlaces caducados u otro fallo con el JSON guardado: reintentar desde la URL.
                Log.w(TAG, "Fallo con el análisis guardado; reintentando desde la URL: ${e.message?.take(300)}")
                YtDlpEngine.discardInfo(applicationContext, p.url)
                rawDir.listFiles()?.forEach { it.deleteRecursively() }
                emit(p, mapOf("status" to "downloading", "progress" to 0.0, "step" to "Reintentando descarga…"))
                // Reintento con los clientes por defecto de yt-dlp: más lento pero más robusto.
                run(null, null)
            }
        }
        if (cancelRequested) throw YoutubeDL.CanceledException()

        val files = downloadedFiles(rawDir)
        if (files.isEmpty()) throw IllegalStateException("yt-dlp terminó pero no se encontró el archivo descargado")

        if (p.isAudioOnly) {
            emit(p, YtDlpEngine.processing("Convirtiendo audio…"))
            return MediaTools.convertAudio(files.maxBy { it.length() }, workDir, p.baseName, p.audioFormat, isCancelled)
        }
        if (files.size == 1 && !needsRemux(files[0])) return files[0]
        emit(p, YtDlpEngine.processing(if (files.size > 1) "Uniendo pistas de audio y video…" else "Ajustando contenedor…"))
        return MediaTools.mux(files, workDir, p.baseName, isCancelled)
    }

    private fun requestCancel() {
        val p = current ?: return stopSelfIfIdle()
        cancelRequested = true
        try {
            YoutubeDL.getInstance().destroyProcessById(p.id)
        } catch (_: Exception) {
        }
    }

    private fun stopSelfIfIdle() {
        if (current == null) stopSelf()
    }

    /** Android 15+: límite de tiempo de los servicios dataSync. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        Log.w(TAG, "Tiempo máximo del servicio en primer plano alcanzado")
        timeoutReached = true
        requestCancel()
    }

    override fun onDestroy() {
        scope.cancel()
        releaseWakeLock()
        super.onDestroy()
    }

    // --- Estado y notificaciones ----------------------------------------------------------

    private fun emit(p: Params, event: Map<String, Any?>) {
        DownloadStateHolder.update(p.id, event)
        val status = event["status"] as? String
        when (status) {
            "completed", "error" -> showResultNotification(p, event)
            "cancelled" -> Unit
            else -> {
                val now = System.currentTimeMillis()
                if (status != lastStatus || now - lastNotifyAt >= NOTIFY_INTERVAL_MS) {
                    lastNotifyAt = now
                    notifySafely(NOTIFICATION_PROGRESS, buildProgressNotification(p.baseName, event))
                }
            }
        }
        lastStatus = status
    }

    private fun buildProgressNotification(title: String, event: Map<String, Any?>?): android.app.Notification {
        val status = event?.get("status") as? String
        val progress = (event?.get("progress") as? Number)?.toInt() ?: 0
        val text = when (status) {
            "downloading" -> listOfNotNull(
                "$progress%",
                event["speed"] as? String,
                (event["eta"] as? String)?.let { "$it restantes" },
            ).joinToString(" · ")
            null -> "Preparando descarga…"
            else -> event["step"] as? String ?: "Procesando…"
        }
        val cancelIntent = PendingIntent.getService(
            this, 1,
            Intent(this, DownloadService::class.java).setAction(ACTION_CANCEL),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_PROGRESS)
            .applyBranding()
            .setContentTitle(title)
            .setContentText(text)
            .setProgress(100, progress, status != "downloading" || progress <= 0)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(openAppIntent())
            .addAction(0, "Cancelar", cancelIntent)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun showResultNotification(p: Params, event: Map<String, Any?>) {
        val ok = event["status"] == "completed"
        val text = if (ok) {
            event["filePath"] as? String ?: p.baseName
        } else {
            (event["error"] as? String)?.lineSequence()?.firstOrNull { it.isNotBlank() } ?: "Error desconocido"
        }
        val notification = NotificationCompat.Builder(this, CHANNEL_RESULT)
            .applyBranding()
            .setContentTitle(if (ok) "Descarga completada" else "Descarga fallida")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(if (ok) "${p.baseName}\n$text" else text))
            .setAutoCancel(true)
            .setContentIntent(openAppIntent())
            .build()
        notifySafely(NOTIFICATION_RESULT, notification)
    }

    /** Logo de la app: silueta en la barra de estado y el icono a color dentro de la notificación. */
    private val largeIcon: Bitmap? by lazy {
        BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher)
    }

    private fun NotificationCompat.Builder.applyBranding(): NotificationCompat.Builder =
        setSmallIcon(R.drawable.ic_stat_notify)
            .setLargeIcon(largeIcon)
            .setColor(BRAND_COLOR)

    private fun openAppIntent(): PendingIntent = PendingIntent.getActivity(
        this, 0,
        Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    @SuppressLint("MissingPermission")
    private fun notifySafely(id: Int, notification: android.app.Notification) {
        val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        if (granted) NotificationManagerCompat.from(this).notify(id, notification)
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_PROGRESS, "Descargas en curso", NotificationManager.IMPORTANCE_LOW)
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_RESULT, "Descargas finalizadas", NotificationManager.IMPORTANCE_DEFAULT)
        )
    }

    // --- Utilidades -----------------------------------------------------------------------

    /** Archivos completos que dejó yt-dlp (sin temporales). */
    private fun downloadedFiles(dir: File): List<File> {
        val tempSuffixes = listOf(".part", ".ytdl", ".temp", ".tmp", ".json")
        return dir.listFiles()
            ?.filter { f -> f.isFile && f.length() > 0 && tempSuffixes.none { f.name.endsWith(it) } && !f.name.contains(".part-Frag") }
            .orEmpty()
    }

    /** HLS nativo de yt-dlp deja MPEG-TS con extensión .mp4, y hay contenedores poco compatibles. */
    private fun needsRemux(file: File): Boolean {
        if (file.extension.lowercase() !in setOf("mp4", "m4v", "mov", "webm")) return MediaTools.hasVideo(file)
        val first = file.inputStream().use { it.read() }
        return first == 0x47
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(PowerManager::class.java)
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MediaDownloader:download").apply {
            setReferenceCounted(false)
            acquire(WAKE_LOCK_TIMEOUT_MS)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
    }
}
