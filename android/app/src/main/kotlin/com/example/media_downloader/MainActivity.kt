package com.example.media_downloader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val FOLDER_CHANNEL = "com.example.media_downloader/folder_picker"
    private val PICK_FOLDER_REQUEST_CODE = 8844
    private var pendingFolderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
