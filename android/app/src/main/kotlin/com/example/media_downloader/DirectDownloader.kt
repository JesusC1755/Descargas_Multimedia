package com.example.media_downloader

import com.yausername.youtubedl_android.YoutubeDL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicLong

/**
 * Descarga HTTP directa de las URLs que entrega [YouTubeFastExtractor]: bloques de 10 MB con
 * `Range` (YouTube limita las peticiones sin rango) repartidos entre varias conexiones, de modo
 * que vídeo y audio se bajan a la vez. Cada bloque se reintenta desde donde se cortó.
 */
class DirectDownloader(
    private val userAgent: String,
    private val isCancelled: () -> Boolean,
) {
    class Part(val url: String, val dest: File, val size: Long)

    /** Avance agregado de todas las partes; [total] es 0 si alguna no informa tamaño. */
    data class Progress(val downloaded: Long, val total: Long, val bytesPerSecond: Double)

    private class Chunk(val part: Part, val start: Long, val end: Long)

    private val downloaded = AtomicLong()

    suspend fun download(parts: List<Part>, onProgress: (Progress) -> Unit) = coroutineScope {
        val queue = ConcurrentLinkedQueue<Chunk>()
        for (part in parts) {
            part.dest.parentFile?.mkdirs()
            if (part.size > 0) {
                RandomAccessFile(part.dest, "rw").use { it.setLength(part.size) }
                var start = 0L
                while (start < part.size) {
                    val end = minOf(start + CHUNK_SIZE, part.size) - 1
                    queue.add(Chunk(part, start, end))
                    start = end + 1
                }
            } else {
                part.dest.delete()
                queue.add(Chunk(part, 0, -1))
            }
        }
        val total = if (parts.all { it.size > 0 }) parts.sumOf { it.size } else 0L

        val reporter = launch {
            var lastBytes = 0L
            var lastAt = System.nanoTime()
            var speed = 0.0
            while (true) {
                delay(REPORT_INTERVAL_MS)
                val now = System.nanoTime()
                val bytes = downloaded.get()
                val instant = (bytes - lastBytes) * 1e9 / (now - lastAt).coerceAtLeast(1)
                speed = if (speed == 0.0) instant else speed * 0.7 + instant * 0.3
                lastBytes = bytes
                lastAt = now
                onProgress(Progress(bytes, total, speed))
            }
        }

        val workers = (1..CONNECTIONS).map {
            async(Dispatchers.IO) {
                while (true) {
                    val chunk = queue.poll() ?: break
                    fetchWithRetries(chunk)
                }
            }
        }
        try {
            workers.awaitAll()
        } finally {
            reporter.cancel()
        }
        onProgress(Progress(downloaded.get(), total, 0.0))
    }

    private fun fetchWithRetries(chunk: Chunk) {
        var start = chunk.start
        var attempt = 0
        while (true) {
            checkCancelled()
            try {
                val written = fetch(chunk, start)
                start += written
                if (chunk.end < 0 || start > chunk.end) return
                throw IOException("Conexión cerrada antes de tiempo")
            } catch (e: YoutubeDL.CanceledException) {
                throw e
            } catch (e: IOException) {
                if (++attempt > MAX_RETRIES) throw IOException("Fallo al descargar: ${e.message}", e)
                Thread.sleep(500L * attempt)
            }
        }
    }

    /** Descarga desde [from] hasta el final del bloque; devuelve los bytes escritos. */
    private fun fetch(chunk: Chunk, from: Long): Long {
        val connection = URL(chunk.part.url).openConnection() as HttpURLConnection
        var written = 0L
        try {
            connection.connectTimeout = 15_000
            connection.readTimeout = 20_000
            connection.setRequestProperty("User-Agent", userAgent)
            val ranged = chunk.end >= 0 || from > 0
            if (ranged) {
                connection.setRequestProperty("Range", "bytes=$from-${if (chunk.end >= 0) chunk.end.toString() else ""}")
            }
            val code = connection.responseCode
            val expected = if (ranged) HttpURLConnection.HTTP_PARTIAL else HttpURLConnection.HTTP_OK
            if (code != expected) throw IOException("HTTP $code")

            RandomAccessFile(chunk.part.dest, "rw").use { file ->
                file.seek(from)
                connection.inputStream.use { input ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    while (true) {
                        checkCancelled()
                        val n = input.read(buffer)
                        if (n < 0) break
                        file.write(buffer, 0, n)
                        written += n
                        downloaded.addAndGet(n.toLong())
                    }
                }
            }
            return written
        } catch (e: IOException) {
            // Lo ya escrito vale: el reintento continúa desde ahí.
            if (written > 0) return written
            throw e
        } finally {
            connection.disconnect()
        }
    }

    private fun checkCancelled() {
        if (isCancelled()) throw YoutubeDL.CanceledException()
    }

    companion object {
        private const val CHUNK_SIZE = 10L * 1024 * 1024
        private const val CONNECTIONS = 4
        private const val MAX_RETRIES = 4
        private const val BUFFER_SIZE = 64 * 1024
        private const val REPORT_INTERVAL_MS = 500L
    }
}
