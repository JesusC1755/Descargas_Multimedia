package com.example.media_downloader

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val TAG = "MediaDownloader"

class MainActivity : FlutterActivity() {
    // Análisis y tareas cortas del motor; las descargas corren en DownloadService.
    private val engineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var progressJob: Job? = null

    private val FOLDER_CHANNEL = "com.example.media_downloader/folder_picker"
    private val ENGINE_CHANNEL = "com.example.media_downloader/engine"
    private val PROGRESS_CHANNEL = "com.example.media_downloader/download_progress"

    private val PICK_FOLDER_REQUEST_CODE = 8844
    private val STORAGE_PERMISSION_REQUEST_CODE = 8845
    private val NOTIFICATION_PERMISSION_REQUEST_CODE = 8846
    private var pendingFolderResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingNotificationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Canal de carpetas de destino (SAF)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FOLDER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFolder" -> pickFolder(result)
                "getDefaultDestination" -> result.success(MediaExporter.defaultDisplayPath)
                "checkTreeAccess" -> {
                    val uri = call.argument<String>("uri")
                    result.success(uri != null && MediaExporter.hasTreeAccess(applicationContext, uri))
                }
                "ensureStoragePermission" -> ensureStoragePermission(result)
                "openFolder" -> result.success(openFolder(call.argument<String>("treeUri")))
                else -> result.notImplemented()
            }
        }

        // 2. Canal de streaming de progreso de descarga
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PROGRESS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                // Reenvía a Flutter el estado que publica DownloadService (cada evento lleva su "id").
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    progressJob?.cancel()
                    progressJob = mainScope.launch {
                        DownloadStateHolder.state.collect { snapshot ->
                            if (snapshot != null && events != null) {
                                events.success(snapshot.event)
                                DownloadStateHolder.markDelivered(snapshot)
                            }
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    progressJob?.cancel()
                    progressJob = null
                }
            }
        )

        // 3. Canal del motor multimedia nativo (youtubedl-android)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ENGINE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> {
                    engineScope.launch {
                        cleanStaleWorkDirs()
                        YtDlpEngine.cleanExpiredInfo(applicationContext)
                        try {
                            YtDlpEngine.ensureInitialized(applicationContext)
                            withContext(Dispatchers.Main) { result.success(true) }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("INIT_ERROR", YtDlpEngine.cleanError(e.message), null)
                            }
                            return@launch
                        }
                        // Actualización en segundo plano (máx. 1 vez cada 24 h); no bloquea el arranque.
                        try {
                            val status = YtDlpEngine.updateIfDue(applicationContext)
                            Log.i(TAG, "Actualización de yt-dlp: $status (versión ${YtDlpEngine.version(applicationContext)})")
                        } catch (e: Exception) {
                            Log.w(TAG, "Actualización de yt-dlp omitida: ${e.message}")
                        }
                    }
                }
                "updateYtDlp" -> {
                    engineScope.launch {
                        try {
                            val status = YtDlpEngine.updateIfDue(applicationContext, force = true)
                            withContext(Dispatchers.Main) { result.success(status) }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("UPDATE_ERROR", YtDlpEngine.cleanError(e.message), null)
                            }
                        }
                    }
                }
                "analyzeUrl" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrEmpty()) {
                        result.error("INVALID_URL", "URL vacía", null)
                        return@setMethodCallHandler
                    }

                    engineScope.launch {
                        try {
                            val started = System.currentTimeMillis()
                            val playerClient = call.argument<String>("playerClient")
                            val analysis = try {
                                YtDlpEngine.analyze(applicationContext, url, playerClient)
                            } catch (e: Exception) {
                                if (playerClient == null) throw e
                                // Respaldo: clientes por defecto de yt-dlp (más lentos en el teléfono por QuickJS).
                                Log.w(TAG, "Análisis con cliente $playerClient falló; reintentando con los de yt-dlp: ${e.message?.take(300)}")
                                YtDlpEngine.analyze(applicationContext, url, null)
                            }
                            Log.i(TAG, "Análisis yt-dlp (cliente: ${playerClient ?: "por defecto"}): ${System.currentTimeMillis() - started} ms")
                            withContext(Dispatchers.Main) {
                                result.success(
                                    mapOf(
                                        "json" to analysis.json,
                                        "debug" to analysis.debug,
                                        "warnings" to analysis.warnings,
                                    )
                                )
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("ANALYZE_ERROR", YtDlpEngine.cleanError(e.message), null)
                            }
                        }
                    }
                }
                "download" -> startDownload(call.arguments as? Map<*, *> ?: emptyMap<String, Any>(), result)
                "cancelDownload" -> {
                    if (DownloadStateHolder.activeId != null) DownloadService.cancel(applicationContext)
                    result.success(true)
                }
                "getActiveDownload" -> result.success(DownloadStateHolder.pendingSnapshot()?.event)
                "ensureNotificationPermission" -> ensureNotificationPermission(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun startDownload(args: Map<*, *>, result: MethodChannel.Result) {
        val id = args["id"] as? String
        val url = args["url"] as? String ?: ""
        if (id.isNullOrEmpty() || url.isEmpty()) {
            result.error("INVALID_ARGS", "Faltan el id o la URL de la descarga", null)
            return
        }
        val initial = mapOf("status" to "downloading", "progress" to 0.0, "step" to "Preparando descarga…")
        if (!DownloadStateHolder.tryBegin(id, initial)) {
            result.error("BUSY", "Ya hay una descarga en curso", null)
            return
        }
        try {
            DownloadService.start(
                applicationContext,
                DownloadService.Params(
                    id = id,
                    url = url,
                    baseName = (args["baseName"] as? String)?.takeIf { it.isNotBlank() } ?: "video",
                    format = args["format"] as? String ?: "",
                    isAudioOnly = args["isAudioOnly"] as? Boolean ?: false,
                    audioFormat = args["audioFormat"] as? String ?: "mp3",
                    treeUri = args["treeUri"] as? String,
                    playerClient = args["playerClient"] as? String,
                ),
            )
            // La descarga corre en DownloadService; el resultado llega por el EventChannel.
            result.success(true)
        } catch (e: Exception) {
            DownloadStateHolder.update(id, mapOf("status" to "error", "error" to "No se pudo iniciar la descarga: ${e.message}"))
            result.error("START_ERROR", "No se pudo iniciar la descarga: ${e.message}", null)
        }
    }

    private fun cleanStaleWorkDirs() {
        val active = DownloadStateHolder.activeId
        DownloadService.workRoot(applicationContext).listFiles()?.forEach { dir ->
            if (dir.name != active) dir.deleteRecursively()
        }
    }

    /** Android 13+: permiso para mostrar la notificación de progreso. Sin él la descarga funciona igual. */
    private fun ensureNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingNotificationResult != null) {
            result.success(false)
            return
        }
        pendingNotificationResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST_CODE)
    }

    override fun onDestroy() {
        progressJob?.cancel()
        mainScope.cancel()
        engineScope.cancel()
        super.onDestroy()
    }

    /** Abre la carpeta en el primer explorador de archivos que acepte alguno de los intents. */
    private fun openFolder(treeUri: String?): Boolean {
        val intents = try {
            MediaExporter.openFolderIntents(treeUri)
        } catch (e: Exception) {
            Log.w(TAG, "URI de carpeta inválido: ${e.message}")
            return false
        }
        for (intent in intents) {
            try {
                startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
            } catch (e: SecurityException) {
                Log.w(TAG, "Sin permiso para abrir ${intent.data}: ${e.message}")
            }
        }
        return false
    }

    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingFolderResult != null) {
            result.error("ALREADY_ACTIVE", "Un selector ya está activo", null)
            return
        }
        pendingFolderResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            }
            startActivityForResult(intent, PICK_FOLDER_REQUEST_CODE)
        } catch (e: Exception) {
            pendingFolderResult?.error("INTENT_ERROR", e.message, null)
            pendingFolderResult = null
        }
    }

    /** Solo Android 7–9 necesita permiso para escribir en Download/; desde Android 10 se usa MediaStore. */
    private fun ensureStoragePermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("ALREADY_ACTIVE", "Ya se está solicitando el permiso", null)
            return
        }
        pendingPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), STORAGE_PERMISSION_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        when (requestCode) {
            STORAGE_PERMISSION_REQUEST_CODE -> {
                pendingPermissionResult?.success(granted)
                pendingPermissionResult = null
            }
            NOTIFICATION_PERMISSION_REQUEST_CODE -> {
                pendingNotificationResult?.success(granted)
                pendingNotificationResult = null
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_FOLDER_REQUEST_CODE) return

        val uri: Uri? = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            pendingFolderResult?.success(null)
        } else {
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
                MediaExporter.releaseOtherTreePermissions(applicationContext, uri)
                pendingFolderResult?.success(
                    mapOf("uri" to uri.toString(), "path" to MediaExporter.displayPathForTree(uri))
                )
            } catch (e: SecurityException) {
                pendingFolderResult?.error("PERMISSION_ERROR", "No se pudo obtener acceso a la carpeta: ${e.message}", null)
            }
        }
        pendingFolderResult = null
    }
}
