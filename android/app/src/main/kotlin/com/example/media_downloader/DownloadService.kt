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
import java.io.File

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

        /** Carpeta privada donde yt-dlp escribe antes de exportar al destino final. */
        fun workRoot(context: Context) = File(context.cacheDir, "downloads")

        fun start(context: Context, p: Params) {
            val intent = Intent(context, DownloadService::class.java).apply {
                action = ACTION_START
                putExtra("id", p.id)
                putExtra("url", p.url)
                putExtra("baseName", p.baseName)
                putExtra("format", p.format)
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
            YtDlpEngine.ensureInitialized(applicationContext)
            YtDlpEngine.awaitPendingUpdate()
            if (cancelRequested) throw YoutubeDL.CanceledException()

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
                    addOption("-o", File(workDir, "${p.baseName}.%(ext)s").absolutePath)
                    addOption("--newline")
                    if (p.isAudioOnly) {
                        // Sin -f se baja Opus y se recodifica; con él, M4A/Opus llegan ya en su códec.
                        if (p.format.isNotEmpty()) addOption("-f", p.format)
                        addOption("-x")
                        addOption("--audio-format", p.audioFormat)
                        addOption("--audio-quality", "0")
                    } else {
                        if (p.format.isNotEmpty()) addOption("-f", p.format)
                        addOption("-S", "vcodec:h264,res,acodec:aac")
                        addOption("--merge-output-format", "mp4")
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

            val cachedInfo = YtDlpEngine.cachedInfoFor(applicationContext, p.url)
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
                    workDir.listFiles()?.forEach { it.deleteRecursively() }
                    emit(p, mapOf("status" to "downloading", "progress" to 0.0, "step" to "Reintentando descarga…"))
                    // Reintento con los clientes por defecto de yt-dlp: más lento pero más robusto.
                    run(null, null)
                }
            }
            if (cancelRequested) throw YoutubeDL.CanceledException()

            val output = findOutputFile(workDir)
                ?: throw IllegalStateException("yt-dlp terminó pero no se encontró el archivo descargado")

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
            .setSmallIcon(android.R.drawable.stat_sys_download)
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
            .setSmallIcon(if (ok) android.R.drawable.stat_sys_download_done else android.R.drawable.stat_notify_error)
            .setContentTitle(if (ok) "Descarga completada" else "Descarga fallida")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(if (ok) "${p.baseName}\n$text" else text))
            .setAutoCancel(true)
            .setContentIntent(openAppIntent())
            .build()
        notifySafely(NOTIFICATION_RESULT, notification)
    }

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

    /** El archivo final es el más grande que no sea temporal de yt-dlp. */
    private fun findOutputFile(dir: File): File? {
        val tempSuffixes = listOf(".part", ".ytdl", ".temp", ".tmp")
        return dir.listFiles()
            ?.filter { f -> f.isFile && tempSuffixes.none { f.name.endsWith(it) } && !f.name.contains(".part-Frag") }
            ?.maxByOrNull { it.length() }
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
