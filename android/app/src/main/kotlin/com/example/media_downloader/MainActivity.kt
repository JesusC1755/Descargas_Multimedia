package com.example.media_downloader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
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
    private var pendingFolderResult: MethodChannel.Result? = null

    private var downloadEventSink: EventChannel.EventSink? = null
    private var activeProcessId: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Canal de selección de carpetas nativas
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FOLDER_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "pickFolder") {
                if (pendingFolderResult != null) {
                    result.error("ALREADY_ACTIVE", "Un selector ya está activo", null)
                    return@setMethodCallHandler
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
            } else {
                result.notImplemented()
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
                            val analysis = YtDlpEngine.analyze(applicationContext, url)
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
                "download" -> {
                    val url = call.argument<String>("url") ?: ""
                    val outputPath = call.argument<String>("outputPath") ?: ""
                    val format = call.argument<String>("format") ?: ""
                    val isAudioOnly = call.argument<Boolean>("isAudioOnly") ?: false
                    val audioFormat = call.argument<String>("audioFormat") ?: "mp3"
                    val expectedFinalPath = call.argument<String>("expectedFinalPath") ?: outputPath

                    val processId = UUID.randomUUID().toString()
                    activeProcessId = processId

                    engineScope.launch {
                        try {
                            YtDlpEngine.ensureInitialized(applicationContext)
                            YtDlpEngine.awaitPendingUpdate()

                            val request = YoutubeDLRequest(url).apply {
                                addOption("-o", outputPath)
                                addOption("--no-playlist")
                                addOption("--newline")
                                if (isAudioOnly) {
                                    addOption("-x")
                                    addOption("--audio-format", audioFormat)
                                    addOption("--audio-quality", "0")
                                } else {
                                    if (format.isNotEmpty()) addOption("-f", format)
                                    addOption("-S", "vcodec:h264,res,acodec:aac")
                                    addOption("--merge-output-format", "mp4")
                                }
                            }

                            YoutubeDL.getInstance().execute(
                                request = request,
                                processId = processId,
                                callback = { progress: Float, etaInSeconds: Long, line: String ->
                                    val event = YtDlpEngine.describeProgress(progress, etaInSeconds, line)
                                    if (event != null) {
                                        runOnUiThread { downloadEventSink?.success(event) }
                                    }
                                }
                            )

                            withContext(Dispatchers.Main) {
                                val completedEvent = mapOf(
                                    "status" to "completed",
                                    "progress" to 100.0,
                                    "filePath" to expectedFinalPath,
                                    "step" to "Descarga completada"
                                )
                                downloadEventSink?.success(completedEvent)
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                val message = YtDlpEngine.cleanError(e.message)
                                val errorEvent = mapOf(
                                    "status" to "error",
                                    "error" to message
                                )
                                downloadEventSink?.success(errorEvent)
                                result.error("DOWNLOAD_ERROR", message, null)
                            }
                        } finally {
                            if (activeProcessId == processId) {
                                activeProcessId = null
                            }
                        }
                    }
                }
                "cancelDownload" -> {
                    activeProcessId?.let { id ->
                        try {
                            YoutubeDL.getInstance().destroyProcessById(id)
                        } catch (_: Exception) {}
                        activeProcessId = null
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_FOLDER_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val uri: Uri? = data.data
                if (uri != null) {
                    try {
                        contentResolver.takePersistableUriPermission(
                            uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                        )
                    } catch (_: Exception) {}

                    val path = getPathFromTreeUri(uri)
                    pendingFolderResult?.success(path)
                } else {
                    pendingFolderResult?.success(null)
                }
            } else {
                pendingFolderResult?.success(null)
            }
            pendingFolderResult = null
        }
    }

    private fun getPathFromTreeUri(uri: Uri): String {
        return try {
            val docId = DocumentsContract.getTreeDocumentId(uri)
            val parts = docId.split(":")
            val type = parts[0]
            val relativePath = if (parts.size > 1) parts[1] else ""

            if ("primary".equals(type, ignoreCase = true)) {
                if (relativePath.isNotEmpty()) {
                    "${Environment.getExternalStorageDirectory().absolutePath}/$relativePath"
                } else {
                    Environment.getExternalStorageDirectory().absolutePath
                }
            } else {
                val externalRoot = File("/storage/$type")
                if (externalRoot.exists()) {
                    if (relativePath.isNotEmpty()) {
                        "${externalRoot.absolutePath}/$relativePath"
                    } else {
                        externalRoot.absolutePath
                    }
                } else {
                    "/storage/$type/$relativePath"
                }
            }
        } catch (e: Exception) {
            uri.path ?: ""
        }
    }
}
