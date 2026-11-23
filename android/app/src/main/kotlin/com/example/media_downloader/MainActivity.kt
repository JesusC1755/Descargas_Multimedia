package com.example.media_downloader

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.Log
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

private const val TAG = "MediaDownloader"

class MainActivity : FlutterActivity() {
    // Ámbito único para el trabajo del motor (en la fase de servicio pasará a DownloadService).
    private val engineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val FOLDER_CHANNEL = "com.example.media_downloader/folder_picker"
    private val ENGINE_CHANNEL = "com.example.media_downloader/engine"
    private val PROGRESS_CHANNEL = "com.example.media_downloader/download_progress"

    private val PICK_FOLDER_REQUEST_CODE = 8844
    private val STORAGE_PERMISSION_REQUEST_CODE = 8845
    private var pendingFolderResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    private var downloadEventSink: EventChannel.EventSink? = null
    private var activeProcessId: String? = null

    /** Carpeta privada donde yt-dlp escribe antes de exportar al destino final. */
    private val workRoot: File get() = File(cacheDir, "downloads")

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
                else -> result.notImplemented()
            }
        }

        // 2. Canal de streaming de progreso de descarga
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PROGRESS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    downloadEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    downloadEventSink = null
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
                    activeProcessId?.let { id ->
                        try {
                            YoutubeDL.getInstance().destroyProcessById(id)
                        } catch (_: Exception) {
                        }
                        activeProcessId = null
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startDownload(args: Map<*, *>, result: MethodChannel.Result) {
        val url = args["url"] as? String ?: ""
        val baseName = (args["baseName"] as? String)?.takeIf { it.isNotBlank() } ?: "video"
        val format = args["format"] as? String ?: ""
        val isAudioOnly = args["isAudioOnly"] as? Boolean ?: false
        val audioFormat = args["audioFormat"] as? String ?: "mp3"
        val treeUri = args["treeUri"] as? String
        val playerClient = args["playerClient"] as? String

        if (url.isEmpty()) {
            result.error("INVALID_URL", "URL vacía", null)
            return
        }
        if (activeProcessId != null) {
            result.error("BUSY", "Ya hay una descarga en curso", null)
            return
        }

        val processId = UUID.randomUUID().toString()
        activeProcessId = processId
        val workDir = File(workRoot, processId).apply { mkdirs() }
        // La descarga corre en segundo plano; el resultado llega por el EventChannel.
        result.success(true)

        engineScope.launch {
            try {
                YtDlpEngine.ensureInitialized(applicationContext)
                YtDlpEngine.awaitPendingUpdate()

                fun buildRequest(info: File?, client: String?): YoutubeDLRequest {
                    // Con el JSON del análisis no se repite la extracción (ni el desafío JS de YouTube).
                    val request = if (info != null) {
                        YoutubeDLRequest(emptyList<String>()).addOption("--load-info-json", info.absolutePath)
                    } else {
                        YoutubeDLRequest(url).addOption("--no-playlist").also {
                            YtDlpEngine.applyPlayerClient(it, client)
                        }
                    }
                    return request.apply {
                        addOption("-o", File(workDir, "$baseName.%(ext)s").absolutePath)
                        addOption("--newline")
                        if (isAudioOnly) {
                            // Sin -f se baja Opus y se recodifica; con él, M4A/Opus llegan ya en su códec.
                            if (format.isNotEmpty()) addOption("-f", format)
                            addOption("-x")
                            addOption("--audio-format", audioFormat)
                            addOption("--audio-quality", "0")
                        } else {
                            if (format.isNotEmpty()) addOption("-f", format)
                            addOption("-S", "vcodec:h264,res,acodec:aac")
                            addOption("--merge-output-format", "mp4")
                        }
                    }
                }

                fun run(info: File?, client: String?) {
                    val started = System.currentTimeMillis()
                    YoutubeDL.getInstance().execute(buildRequest(info, client), processId) { progress: Float, eta: Long, line: String ->
                        YtDlpEngine.describeProgress(progress, eta, line)?.let { emit(it) }
                    }
                    val mode = if (info != null) "info-json" else "url"
                    Log.i(TAG, "Descarga yt-dlp ($mode): ${System.currentTimeMillis() - started} ms")
                }

                val cachedInfo = YtDlpEngine.cachedInfoFor(applicationContext, url)
                if (cachedInfo == null) {
                    run(null, playerClient)
                } else {
                    try {
                        run(cachedInfo, null)
                    } catch (e: YoutubeDL.CanceledException) {
                        throw e
                    } catch (e: Exception) {
                        // Enlaces caducados u otro fallo con el JSON guardado: reintentar desde la URL.
                        Log.w(TAG, "Fallo con el análisis guardado; reintentando desde la URL: ${e.message?.take(300)}")
                        YtDlpEngine.discardInfo(applicationContext, url)
                        workDir.listFiles()?.forEach { it.deleteRecursively() }
                        emit(mapOf("status" to "downloading", "progress" to 0.0, "step" to "Reintentando descarga…"))
                        // Reintento con los clientes por defecto de yt-dlp: más lento pero más robusto.
                        run(null, null)
                    }
                }

                val output = findOutputFile(workDir)
                    ?: throw IllegalStateException("yt-dlp terminó pero no se encontró el archivo descargado")

                emit(
                    mapOf(
                        "status" to "processing",
                        "progress" to 99.0,
                        "step" to "Guardando en la carpeta de destino…",
                    )
                )
                val exported = MediaExporter.export(applicationContext, output, treeUri)
                Log.i(TAG, "Archivo exportado: ${exported.displayPath} (${exported.uri})")

                emit(
                    mapOf(
                        "status" to "completed",
                        "progress" to 100.0,
                        "filePath" to exported.displayPath,
                        "uri" to exported.uri.toString(),
                        "step" to "¡Descarga Exitosa!",
                    )
                )
            } catch (e: Exception) {
                Log.w(TAG, "Descarga fallida", e)
                emit(mapOf("status" to "error", "error" to YtDlpEngine.cleanError(e.message)))
            } finally {
                workDir.deleteRecursively()
                if (activeProcessId == processId) activeProcessId = null
            }
        }
    }

    private fun emit(event: Map<String, Any?>) {
        runOnUiThread { downloadEventSink?.success(event) }
    }

    /** El archivo final es el más grande que no sea temporal de yt-dlp. */
    private fun findOutputFile(dir: File): File? {
        val tempSuffixes = listOf(".part", ".ytdl", ".temp", ".tmp")
        return dir.listFiles()
            ?.filter { f -> f.isFile && tempSuffixes.none { f.name.endsWith(it) } && !f.name.contains(".part-Frag") }
            ?.maxByOrNull { it.length() }
    }

    private fun cleanStaleWorkDirs() {
        workRoot.listFiles()?.forEach { dir ->
            if (dir.name != activeProcessId) dir.deleteRecursively()
        }
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
        if (requestCode == STORAGE_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
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
