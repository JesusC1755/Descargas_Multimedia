package com.example.media_downloader

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import kotlinx.coroutines.suspendCancellableCoroutine
import java.io.File
import java.io.IOException
import kotlin.coroutines.resume

/**
 * Copia un archivo descargado en la carpeta privada de la app a su destino público.
 *
 * Desde Android 11 (scoped storage) no se puede escribir por ruta directa en carpetas
 * arbitrarias: `Movies/` rechaza archivos que no sean video (como los `.part` de yt-dlp)
 * y la tarjeta SD no admite escritura por ruta. Por eso se usan las API oficiales:
 * - Carpeta elegida por el usuario → SAF (`DocumentsContract.createDocument`).
 * - Carpeta predeterminada → MediaStore `Download/` (API 29+) o copia directa (API 24–28).
 */
object MediaExporter {

    data class Exported(val uri: Uri, val displayPath: String)

    val defaultDisplayPath: String
        get() = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).absolutePath

    suspend fun export(context: Context, source: File, treeUri: String?): Exported {
        val mime = mimeTypeFor(source)
        return when {
            treeUri != null -> exportToTree(context, source, Uri.parse(treeUri), mime)
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> exportToMediaStore(context, source, mime)
            else -> exportLegacy(context, source, mime)
        }
    }

    /** ¿Seguimos teniendo permiso persistente de escritura sobre la carpeta SAF? */
    fun hasTreeAccess(context: Context, treeUri: String): Boolean {
        val uri = Uri.parse(treeUri)
        return context.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isWritePermission }
    }

    /** Conserva solo el permiso de la carpeta activa (Android limita cuántos se pueden persistir). */
    fun releaseOtherTreePermissions(context: Context, keep: Uri) {
        val resolver = context.contentResolver
        resolver.persistedUriPermissions
            .filter { it.uri != keep }
            .forEach {
                try {
                    resolver.releasePersistableUriPermission(
                        it.uri,
                        android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                } catch (_: SecurityException) {
                }
            }
    }

    /** Ruta legible de una carpeta SAF, solo para mostrarla (no se usa para escribir). */
    fun displayPathForTree(treeUri: Uri): String {
        return try {
            val docId = DocumentsContract.getTreeDocumentId(treeUri)
            val parts = docId.split(":", limit = 2)
            val volume = parts[0]
            val relative = parts.getOrElse(1) { "" }
            val root = if ("primary".equals(volume, ignoreCase = true)) {
                Environment.getExternalStorageDirectory().absolutePath
            } else {
                "/storage/$volume"
            }
            if (relative.isEmpty()) root else "$root/$relative"
        } catch (_: Exception) {
            treeUri.toString()
        }
    }

    private fun exportToTree(context: Context, source: File, treeUri: Uri, mime: String): Exported {
        val resolver = context.contentResolver
        val parent = DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri)
        )
        // El proveedor agrega " (1)", " (2)"… si ya existe un archivo con ese nombre.
        val created = DocumentsContract.createDocument(resolver, parent, mime, source.name)
            ?: throw IOException("No se pudo crear el archivo en la carpeta seleccionada")
        try {
            copy(context, source, created)
        } catch (e: Exception) {
            try {
                DocumentsContract.deleteDocument(resolver, created)
            } catch (_: Exception) {
            }
            throw e
        }
        val name = queryDisplayName(context, created) ?: source.name
        return Exported(created, "${displayPathForTree(treeUri)}/$name")
    }

    private fun exportToMediaStore(context: Context, source: File, mime: String): Exported {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, source.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("No se pudo registrar el archivo en Descargas")
        try {
            copy(context, source, uri)
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        // MediaStore también renombra con " (1)" si el nombre ya existe.
        val name = queryDisplayName(context, uri) ?: source.name
        return Exported(uri, "$defaultDisplayPath/$name")
    }

    @Suppress("DEPRECATION")
    private suspend fun exportLegacy(context: Context, source: File, mime: String): Exported {
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!dir.exists() && !dir.mkdirs()) throw IOException("No se pudo crear la carpeta Descargas")
        val target = uniqueFile(dir, source.name)
        source.copyTo(target)
        val uri = scanFile(context, target, mime) ?: Uri.fromFile(target)
        return Exported(uri, target.absolutePath)
    }

    private fun copy(context: Context, source: File, target: Uri) {
        val out = context.contentResolver.openOutputStream(target)
            ?: throw IOException("No se pudo abrir el archivo de destino")
        out.use { o -> source.inputStream().use { it.copyTo(o, bufferSize = 256 * 1024) } }
    }

    private fun queryDisplayName(context: Context, uri: Uri): String? = try {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }
    } catch (_: Exception) {
        null
    }

    private fun uniqueFile(dir: File, name: String): File {
        var candidate = File(dir, name)
        if (!candidate.exists()) return candidate
        val base = name.substringBeforeLast('.')
        val ext = name.substringAfterLast('.', "")
        var i = 1
        while (candidate.exists()) {
            candidate = File(dir, if (ext.isEmpty()) "$base ($i)" else "$base ($i).$ext")
            i++
        }
        return candidate
    }

    private suspend fun scanFile(context: Context, file: File, mime: String): Uri? =
        suspendCancellableCoroutine { cont ->
            MediaScannerConnection.scanFile(context, arrayOf(file.absolutePath), arrayOf(mime)) { _, uri ->
                if (cont.isActive) cont.resume(uri)
            }
        }

    fun mimeTypeFor(file: File): String {
        val ext = file.extension.lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            ?: when (ext) {
                "opus" -> "audio/ogg"
                "flac" -> "audio/flac"
                "m4a" -> "audio/mp4"
                else -> "application/octet-stream"
            }
    }
}
