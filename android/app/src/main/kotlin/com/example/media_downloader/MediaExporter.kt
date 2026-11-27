package com.example.media_downloader

import android.app.DownloadManager
import android.content.ContentValues
import android.content.Intent
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
 * - Carpeta predeterminada → MediaStore `Download/<subdir>` (API 29+) o copia directa (API 24–28).
 */
object MediaExporter {

    data class Exported(val uri: Uri, val displayPath: String)

    private val downloadsDir: File
        get() = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)

    val defaultDisplayPath: String
        get() = downloadsDir.absolutePath

    private fun downloadsDir(subdir: String?) = if (subdir == null) downloadsDir else File(downloadsDir, subdir)

    /** [subdir]: subcarpeta dentro de `Download/` (ej. `MediaDownloader/Video`) si no hay [treeUri]. */
    suspend fun export(context: Context, source: File, treeUri: String?, subdir: String?): Exported {
        val mime = mimeTypeFor(source)
        val relative = subdir?.trim('/')?.takeIf { it.isNotEmpty() }
        return when {
            treeUri != null -> exportToTree(context, source, Uri.parse(treeUri), mime)
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> exportToMediaStore(context, source, mime, relative)
            else -> exportLegacy(context, source, mime, relative)
        }
    }

    /** ¿Seguimos teniendo permiso persistente de escritura sobre la carpeta SAF? */
    fun hasTreeAccess(context: Context, treeUri: String): Boolean {
        val uri = Uri.parse(treeUri)
        return context.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isWritePermission }
    }

    /** Conserva solo los permisos de las carpetas en uso (Android limita cuántos se pueden persistir). */
    fun releaseUnusedTreePermissions(context: Context, keep: Set<Uri>) {
        val resolver = context.contentResolver
        resolver.persistedUriPermissions
            .filter { it.uri !in keep }
            .forEach {
                try {
                    resolver.releasePersistableUriPermission(
                        it.uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                } catch (_: SecurityException) {
                }
            }
    }

    /**
     * Intents para abrir la carpeta de destino en un explorador de archivos, en orden de
     * preferencia. No existe una forma estándar, así que se prueban varias.
     */
    fun openFolderIntents(treeUri: String?, subdir: String?): List<Intent> {
        val flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
        val dirType = DocumentsContract.Document.MIME_TYPE_DIR
        val intents = mutableListOf<Intent>()
        if (treeUri != null) {
            val tree = Uri.parse(treeUri)
            val docId = DocumentsContract.getTreeDocumentId(tree)
            // URI de documento simple (lo que espera el explorador del sistema) y, si no, el del árbol SAF.
            intents += Intent(Intent.ACTION_VIEW)
                .setDataAndType(DocumentsContract.buildDocumentUri(tree.authority, docId), dirType)
                .addFlags(flags)
            intents += Intent(Intent.ACTION_VIEW)
                .setDataAndType(DocumentsContract.buildDocumentUriUsingTree(tree, docId), dirType)
                .addFlags(flags)
        } else {
            // La subcarpeta solo existe tras la primera descarga; si no, se abre Download/.
            val relative = subdir?.trim('/')?.takeIf { it.isNotEmpty() && File(downloadsDir, it).isDirectory }
            val path = listOfNotNull(Environment.DIRECTORY_DOWNLOADS, relative).joinToString("/")
            intents += Intent(Intent.ACTION_VIEW)
                .setDataAndType(DocumentsContract.buildDocumentUri(EXTERNAL_STORAGE_AUTHORITY, "primary:$path"), dirType)
                .addFlags(flags)
            intents += Intent(DownloadManager.ACTION_VIEW_DOWNLOADS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return intents
    }

    private const val EXTERNAL_STORAGE_AUTHORITY = "com.android.externalstorage.documents"

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

    private fun exportToMediaStore(context: Context, source: File, mime: String, subdir: String?): Exported {
        val resolver = context.contentResolver
        val relativePath = listOfNotNull(Environment.DIRECTORY_DOWNLOADS, subdir).joinToString("/") + "/"
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, source.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
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
        val dir = downloadsDir(subdir)
        return Exported(uri, File(dir, name).absolutePath)
    }

    @Suppress("DEPRECATION")
    private suspend fun exportLegacy(context: Context, source: File, mime: String, subdir: String?): Exported {
        val dir = downloadsDir(subdir)
        if (!dir.exists() && !dir.mkdirs()) throw IOException("No se pudo crear la carpeta ${dir.absolutePath}")
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
