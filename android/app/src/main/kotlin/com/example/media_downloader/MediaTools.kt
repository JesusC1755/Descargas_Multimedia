package com.example.media_downloader

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import com.yausername.youtubedl_android.YoutubeDL
import java.io.Closeable
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Sustituye a FFmpeg con las APIs multimedia de Android (sin peso extra en el APK):
 * - [mux]: une vídeo y audio, o cambia de contenedor, sin recodificar (MediaExtractor + MediaMuxer).
 * - [convertAudio]: M4A/Opus/FLAC/MP3; copia el audio si ya viene en ese códec y, si no,
 *   lo decodifica con MediaCodec y lo codifica (MP3 con LAME, el resto con MediaCodec).
 */
object MediaTools {
    private const val TIMEOUT_US = 10_000L
    private const val MIN_SAMPLE_BUFFER = 4 * 1024 * 1024

    private const val MIME_AAC = MediaFormat.MIMETYPE_AUDIO_AAC
    private const val MIME_OPUS = MediaFormat.MIMETYPE_AUDIO_OPUS
    private const val MIME_FLAC = MediaFormat.MIMETYPE_AUDIO_FLAC
    private const val MIME_MP3 = MediaFormat.MIMETYPE_AUDIO_MPEG

    private val WEBM_VIDEO = setOf(MediaFormat.MIMETYPE_VIDEO_VP8, MediaFormat.MIMETYPE_VIDEO_VP9)
    private val WEBM_AUDIO = setOf(MIME_OPUS, MediaFormat.MIMETYPE_AUDIO_VORBIS)

    private val OPUS_RATES = setOf(8000, 12000, 16000, 24000, 48000)

    private class Track(val file: File, val index: Int, val format: MediaFormat) {
        val mime: String = format.getString(MediaFormat.KEY_MIME) ?: ""
        val isVideo get() = mime.startsWith("video/")
        val isAudio get() = mime.startsWith("audio/")
    }

    private fun tracksOf(file: File): List<Track> {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(file.absolutePath)
            return (0 until extractor.trackCount).map { Track(file, it, extractor.getTrackFormat(it)) }
        } finally {
            extractor.release()
        }
    }

    fun hasVideo(file: File): Boolean = try {
        tracksOf(file).any { it.isVideo }
    } catch (_: Exception) {
        false
    }

    /**
     * Une la primera pista de vídeo y la primera de audio de [inputs] sin recodificar.
     * Devuelve `[baseName].mp4`, o `.webm` si los códecs solo caben en WebM (VP8/VP9 con Opus/Vorbis).
     */
    fun mux(inputs: List<File>, dir: File, baseName: String, isCancelled: () -> Boolean): File {
        val all = inputs.flatMap(::tracksOf)
        val video = all.firstOrNull { it.isVideo }
        val audio = all.firstOrNull { it.isAudio }
        val tracks = listOfNotNull(video, audio)
        if (tracks.isEmpty()) throw IOException("El archivo descargado no contiene audio ni vídeo")

        val webm = tracks.all { it.mime in WEBM_VIDEO || it.mime in WEBM_AUDIO } && video?.mime in WEBM_VIDEO
        val out = File(dir, "$baseName.${if (webm) "webm" else "mp4"}")
        val container = if (webm) MediaMuxer.OutputFormat.MUXER_OUTPUT_WEBM else MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4
        try {
            copyTracks(tracks, out, container, isCancelled)
        } catch (e: YoutubeDL.CanceledException) {
            throw e
        } catch (e: Exception) {
            out.delete()
            val codecs = tracks.joinToString(" + ") { it.mime }
            throw IOException("No se pudieron unir las pistas ($codecs): ${e.message}", e)
        }
        return out
    }

    /**
     * Deja el audio de [input] en [target] (m4a, opus, flac o mp3) como `[baseName].[target]`.
     * Si el códec ya coincide solo se cambia de contenedor; si no, se recodifica.
     */
    fun convertAudio(input: File, dir: File, baseName: String, target: String, isCancelled: () -> Boolean): File {
        val track = tracksOf(input).firstOrNull { it.isAudio }
            ?: throw IOException("El archivo descargado no contiene audio")
        val out = File(dir, "$baseName.$target")
        if (out.absolutePath == input.absolutePath) throw IOException("Ruta de salida inválida")

        val copyContainer = when {
            target == "m4a" && track.mime == MIME_AAC -> MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4
            target == "opus" && track.mime == MIME_OPUS && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
                MediaMuxer.OutputFormat.MUXER_OUTPUT_OGG
            else -> null
        }
        if (copyContainer != null) {
            try {
                copyTracks(listOf(track), out, copyContainer, isCancelled)
                return out
            } catch (e: YoutubeDL.CanceledException) {
                throw e
            } catch (_: Exception) {
                out.delete() // Se intenta recodificando.
            }
        }
        if ((target == "mp3" && track.mime == MIME_MP3 && input.extension.equals("mp3", true)) ||
            (target == "flac" && track.mime == MIME_FLAC && input.extension.equals("flac", true))
        ) {
            input.copyTo(out, overwrite = true)
            return out
        }

        val sink: PcmSink = when (target) {
            "mp3" -> LameSink(out)
            "flac" -> EncoderSink(out, MIME_FLAC, bitRate = null, container = null)
            "m4a" -> EncoderSink(out, MIME_AAC, bitRate = 192_000, container = MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            "opus" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    throw IOException("Convertir a Opus requiere Android 10 o superior")
                }
                ResamplingSink(
                    48_000, OPUS_RATES,
                    EncoderSink(out, MIME_OPUS, bitRate = 128_000, container = MediaMuxer.OutputFormat.MUXER_OUTPUT_OGG),
                )
            }
            else -> throw IOException("Formato de audio no soportado: $target")
        }
        try {
            sink.use { decode(track, it, isCancelled) }
        } catch (e: Exception) {
            out.delete()
            throw e
        }
        return out
    }

    // --- Copia sin recodificar -------------------------------------------------------------

    private fun copyTracks(tracks: List<Track>, out: File, container: Int, isCancelled: () -> Boolean) {
        out.delete()
        val muxer = MediaMuxer(out.absolutePath, container)
        val extractors = ArrayList<MediaExtractor>()
        var completed = false
        try {
            val targets = IntArray(tracks.size)
            var bufferSize = MIN_SAMPLE_BUFFER
            tracks.forEachIndexed { i, track ->
                extractors += MediaExtractor().apply {
                    setDataSource(track.file.absolutePath)
                    selectTrack(track.index)
                }
                targets[i] = muxer.addTrack(track.format)
                if (track.format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                    bufferSize = maxOf(bufferSize, track.format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
                }
                if (track.isVideo && track.format.containsKey(MediaFormat.KEY_ROTATION)) {
                    muxer.setOrientationHint(track.format.getInteger(MediaFormat.KEY_ROTATION))
                }
            }
            muxer.start()

            val buffer = ByteBuffer.allocateDirect(bufferSize)
            val info = MediaCodec.BufferInfo()
            val finished = BooleanArray(tracks.size)
            // El AAC con lista de edición (Facebook, Instagram…) empieza con marcas negativas
            // (silencio inicial del codificador): se desplaza todo para que empiece en 0.
            val firstTime = extractors.filter { it.sampleTrackIndex >= 0 }.minOfOrNull { it.sampleTime } ?: 0L
            val shift = if (firstTime < 0) -firstTime else 0L
            while (true) {
                if (isCancelled()) throw YoutubeDL.CanceledException()
                // Se escribe siempre la muestra más temprana: pistas intercaladas.
                var next = -1
                var earliest = Long.MAX_VALUE
                for (i in tracks.indices) {
                    if (finished[i]) continue
                    // Fin de pista: sin muestra seleccionada (la marca de tiempo puede ser negativa).
                    if (extractors[i].sampleTrackIndex < 0) {
                        finished[i] = true
                        continue
                    }
                    val time = extractors[i].sampleTime
                    if (time < earliest) {
                        earliest = time
                        next = i
                    }
                }
                if (next < 0) break

                val extractor = extractors[next]
                buffer.clear()
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) {
                    finished[next] = true
                    continue
                }
                val keyFrame = extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0
                val time = (extractor.sampleTime + shift).coerceAtLeast(0L)
                info.set(0, size, time, if (keyFrame) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
                muxer.writeSampleData(targets[next], buffer, info)
                extractor.advance()
            }
            muxer.stop()
            completed = true
        } finally {
            extractors.forEach { it.release() }
            try {
                muxer.release()
            } catch (_: Exception) {
            }
            if (!completed) out.delete()
        }
    }

    // --- Decodificación a PCM --------------------------------------------------------------

    private fun decode(track: Track, sink: PcmSink, isCancelled: () -> Boolean) {
        val extractor = MediaExtractor().apply {
            setDataSource(track.file.absolutePath)
            selectTrack(track.index)
        }
        val decoder = MediaCodec.createDecoderByType(track.mime)
        try {
            decoder.configure(track.format, null, null, 0)
            decoder.start()
            var sampleRate = track.format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = track.format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var isFloat = false
            var inputDone = false
            var started = false
            val info = MediaCodec.BufferInfo()
            var shorts = ShortArray(0)

            while (true) {
                if (isCancelled()) throw YoutubeDL.CanceledException()
                if (!inputDone) {
                    val index = decoder.dequeueInputBuffer(TIMEOUT_US)
                    if (index >= 0) {
                        val buffer = decoder.getInputBuffer(index)!!
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                val index = decoder.dequeueOutputBuffer(info, TIMEOUT_US)
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    // HE-AAC (SBR) suele cambiar aquí la frecuencia real.
                    val format = decoder.outputFormat
                    sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    isFloat = format.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                        format.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                } else if (index >= 0) {
                    if (info.size > 0) {
                        val buffer = decoder.getOutputBuffer(index)!!
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        val ordered = buffer.slice().order(ByteOrder.nativeOrder())
                        val count = if (isFloat) info.size / 4 else info.size / 2
                        if (shorts.size < count) shorts = ShortArray(count)
                        if (isFloat) {
                            val floats = ordered.asFloatBuffer()
                            for (i in 0 until count) {
                                shorts[i] = (floats.get(i).coerceIn(-1f, 1f) * 32767f).roundToInt().toShort()
                            }
                        } else {
                            ordered.asShortBuffer().get(shorts, 0, count)
                        }
                        val frames = count / channels
                        if (channels > 2) {
                            // Más de dos canales (5.1…): se conservan frontal izquierdo y derecho.
                            for (f in 0 until frames) {
                                shorts[f * 2] = shorts[f * channels]
                                shorts[f * 2 + 1] = shorts[f * channels + 1]
                            }
                        }
                        if (!started) {
                            sink.start(sampleRate, min(channels, 2))
                            started = true
                        }
                        sink.write(shorts, frames)
                    }
                    decoder.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
            if (!started) throw IOException("No se pudo decodificar el audio (${track.mime})")
            sink.finish()
        } finally {
            try {
                decoder.stop()
            } catch (_: Exception) {
            }
            decoder.release()
            extractor.release()
        }
    }

    // --- Destinos del PCM ------------------------------------------------------------------

    private interface PcmSink : Closeable {
        fun start(sampleRate: Int, channels: Int)

        /** [pcm]: PCM 16 bits intercalado con [frames] muestras por canal. */
        fun write(pcm: ShortArray, frames: Int)
        fun finish()
    }

    /** MP3 VBR de máxima calidad con LAME, con trama Xing para que la duración sea exacta. */
    private class LameSink(private val out: File) : PcmSink {
        private var handle = 0L
        private var file: RandomAccessFile? = null
        private var buffer = ByteArray(16 * 1024)

        override fun start(sampleRate: Int, channels: Int) {
            handle = Mp3Encoder.nativeInit(sampleRate, channels, 0)
            if (handle == 0L) throw IOException("LAME no admite $sampleRate Hz con $channels canales")
            file = RandomAccessFile(out, "rw").apply { setLength(0) }
        }

        override fun write(pcm: ShortArray, frames: Int) {
            val needed = frames * 5 / 4 + 7200
            if (buffer.size < needed) buffer = ByteArray(needed)
            val n = Mp3Encoder.nativeEncode(handle, pcm, frames, buffer)
            if (n < 0) throw IOException("Error de LAME ($n)")
            file!!.write(buffer, 0, n)
        }

        override fun finish() {
            val n = Mp3Encoder.nativeFlush(handle, buffer)
            if (n > 0) file!!.write(buffer, 0, n)
            val tag = ByteArray(8 * 1024)
            val size = Mp3Encoder.nativeLameTag(handle, tag)
            if (size in 1..tag.size) {
                file!!.seek(0)
                file!!.write(tag, 0, size)
            }
        }

        override fun close() {
            if (handle != 0L) Mp3Encoder.nativeClose(handle)
            handle = 0L
            file?.close()
            file = null
        }
    }

    /**
     * Codificador de Android ([mime]) hacia un contenedor de MediaMuxer, o hacia un archivo FLAC
     * nativo si [container] es null (MediaMuxer no escribe .flac).
     */
    private class EncoderSink(
        private val out: File,
        private val mime: String,
        private val bitRate: Int?,
        private val container: Int?,
    ) : PcmSink {
        private var codec: MediaCodec? = null
        private var muxer: MediaMuxer? = null
        private var raw: RandomAccessFile? = null
        private var track = -1
        private var muxerStarted = false
        private var headerWritten = false
        private var sampleRate = 0
        private var channels = 0
        private var framesQueued = 0L
        private val info = MediaCodec.BufferInfo()

        override fun start(sampleRate: Int, channels: Int) {
            this.sampleRate = sampleRate
            this.channels = channels
            val format = MediaFormat.createAudioFormat(mime, sampleRate, channels)
            bitRate?.let { format.setInteger(MediaFormat.KEY_BIT_RATE, it) }
            if (mime == MIME_AAC) {
                format.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            }
            if (mime == MIME_FLAC) format.setInteger(MediaFormat.KEY_FLAC_COMPRESSION_LEVEL, 5)
            codec = MediaCodec.createEncoderByType(mime).apply {
                configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                start()
            }
            out.delete()
            if (container != null) {
                muxer = MediaMuxer(out.absolutePath, container)
            } else {
                raw = RandomAccessFile(out, "rw").apply { setLength(0) }
            }
        }

        private fun ptsUs() = framesQueued * 1_000_000L / sampleRate

        override fun write(pcm: ShortArray, frames: Int) {
            val codec = codec!!
            var offset = 0
            while (offset < frames) {
                val index = codec.dequeueInputBuffer(TIMEOUT_US)
                if (index >= 0) {
                    val buffer = codec.getInputBuffer(index)!!
                    buffer.clear()
                    val n = min(buffer.capacity() / (2 * channels), frames - offset)
                    buffer.order(ByteOrder.nativeOrder()).asShortBuffer().put(pcm, offset * channels, n * channels)
                    codec.queueInputBuffer(index, 0, n * 2 * channels, ptsUs(), 0)
                    framesQueued += n
                    offset += n
                }
                drain(untilEos = false)
            }
        }

        override fun finish() {
            val codec = codec!!
            while (true) {
                val index = codec.dequeueInputBuffer(TIMEOUT_US)
                if (index >= 0) {
                    codec.queueInputBuffer(index, 0, 0, ptsUs(), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    break
                }
                drain(untilEos = false)
            }
            drain(untilEos = true)
            muxer?.let {
                if (!muxerStarted) throw IOException("El codificador no produjo audio")
                it.stop()
            }
            raw?.let { patchFlacTotalSamples(it) }
        }

        private fun drain(untilEos: Boolean) {
            val codec = codec!!
            var idle = 0
            while (true) {
                val index = codec.dequeueOutputBuffer(info, if (untilEos) TIMEOUT_US else 0)
                when {
                    index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        if (!untilEos || ++idle > 500) return
                    }
                    index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val format = codec.outputFormat
                        muxer?.let {
                            track = it.addTrack(format)
                            it.start()
                            muxerStarted = true
                        }
                        if (raw != null && format.containsKey("csd-0")) writeFlacHeader(format.getByteBuffer("csd-0")!!)
                    }
                    index >= 0 -> {
                        idle = 0
                        val buffer = codec.getOutputBuffer(index)!!
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                        if (raw != null) {
                            if (isConfig || (!headerWritten && startsWithFlacMarker(buffer))) {
                                writeFlacHeader(buffer)
                            } else if (info.size > 0) {
                                if (!headerWritten) throw IOException("El codificador FLAC no entregó la cabecera")
                                val bytes = ByteArray(info.size)
                                buffer.get(bytes)
                                raw!!.write(bytes)
                            }
                        } else if (!isConfig && info.size > 0 && muxerStarted) {
                            muxer!!.writeSampleData(track, buffer, info)
                        }
                        codec.releaseOutputBuffer(index, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                    }
                }
            }
        }

        private fun startsWithFlacMarker(buffer: ByteBuffer): Boolean {
            if (buffer.remaining() < 4) return false
            val p = buffer.position()
            return buffer.get(p) == 'f'.code.toByte() && buffer.get(p + 1) == 'L'.code.toByte() &&
                buffer.get(p + 2) == 'a'.code.toByte() && buffer.get(p + 3) == 'C'.code.toByte()
        }

        /** Cabecera del FLAC: "fLaC" + bloques de metadatos (STREAMINFO), una sola vez. */
        private fun writeFlacHeader(buffer: ByteBuffer) {
            if (headerWritten || buffer.remaining() == 0) return
            val bytes = ByteArray(buffer.remaining())
            buffer.duplicate().get(bytes)
            val file = raw!!
            if (!startsWithFlacMarker(ByteBuffer.wrap(bytes))) file.write("fLaC".toByteArray())
            file.write(bytes)
            headerWritten = true
        }

        /** El codificador no puede volver atrás a escribir el total de muestras en STREAMINFO. */
        private fun patchFlacTotalSamples(file: RandomAccessFile) {
            if (file.length() < 42) return
            file.seek(4)
            if (file.read() and 0x7F != 0) return // El primer bloque no es STREAMINFO.
            file.seek(18)
            val packed = file.readLong()
            val mask = 0xF_FFFF_FFFFL
            file.seek(18)
            file.writeLong((packed and mask.inv()) or (framesQueued and mask))
        }

        override fun close() {
            codec?.let {
                try {
                    it.stop()
                } catch (_: Exception) {
                }
                it.release()
            }
            codec = null
            try {
                muxer?.release()
            } catch (_: Exception) {
            }
            muxer = null
            raw?.close()
            raw = null
        }
    }

    /**
     * Remuestreo polifásico con sinc enventanada (Blackman, 32 coeficientes), p. ej. de 44,1 a 48 kHz
     * para Opus. Si la frecuencia de entrada está en [accepted], pasa el audio tal cual.
     */
    private class ResamplingSink(
        private val outRate: Int,
        private val accepted: Set<Int>,
        private val next: PcmSink,
    ) : PcmSink {
        private var passthrough = false
        private var channels = 0
        private var up = 1
        private var down = 1
        private var table = FloatArray(0)
        private var input = FloatArray(0)
        private var inFrames = 0
        private var base = 0L
        private var totalIn = 0L
        private var outIndex = 0L
        private var outBuf = ShortArray(0)
        private var outCount = 0

        override fun start(sampleRate: Int, channels: Int) {
            this.channels = channels
            passthrough = sampleRate in accepted
            if (passthrough) {
                next.start(sampleRate, channels)
                return
            }
            val g = gcd(sampleRate, outRate)
            up = outRate / g
            down = sampleRate / g
            if (up > 4096) throw IOException("Frecuencia de muestreo no soportada: $sampleRate Hz")
            val cutoff = min(1.0, up.toDouble() / down) * 0.97
            table = FloatArray(up * TAPS)
            for (phase in 0 until up) {
                val frac = phase.toDouble() / up
                val row = DoubleArray(TAPS)
                for (k in 0 until TAPS) {
                    val d = frac + HALF - 1 - k
                    val x = PI * cutoff * d
                    val sinc = if (x == 0.0) 1.0 else sin(x) / x
                    val w = if (abs(d) < HALF) 0.42 + 0.5 * cos(PI * d / HALF) + 0.08 * cos(2 * PI * d / HALF) else 0.0
                    row[k] = sinc * w
                }
                val sum = row.sum()
                for (k in 0 until TAPS) table[phase * TAPS + k] = (row[k] / sum).toFloat()
            }
            outBuf = ShortArray(4096 * channels)
            next.start(outRate, channels)
        }

        override fun write(pcm: ShortArray, frames: Int) {
            if (passthrough) return next.write(pcm, frames)
            val needed = (inFrames + frames) * channels
            if (input.size < needed) input = input.copyOf(maxOf(needed, input.size * 2))
            val offset = inFrames * channels
            for (i in 0 until frames * channels) input[offset + i] = pcm[i] / 32768f
            inFrames += frames
            totalIn += frames
            produce(final = false)
        }

        private fun produce(final: Boolean) {
            while (true) {
                val position = outIndex * down
                val i = position / up
                val phase = (position % up).toInt()
                if (final) {
                    if (i >= totalIn) break
                } else if (i + HALF >= base + inFrames) {
                    break
                }
                val first = (i - HALF + 1 - base).toInt()
                val row = phase * TAPS
                for (c in 0 until channels) {
                    var acc = 0f
                    for (k in 0 until TAPS) {
                        val idx = first + k
                        if (idx in 0 until inFrames) acc += input[idx * channels + c] * table[row + k]
                    }
                    outBuf[outCount * channels + c] = (acc.coerceIn(-1f, 1f) * 32767f).roundToInt().toShort()
                }
                outCount++
                outIndex++
                if (outCount * channels == outBuf.size) flush()
            }
            flush()
            // Se descartan las muestras que ya no necesita ninguna salida futura.
            val keepFrom = ((outIndex * down / up) - HALF + 1 - base).coerceIn(0L, inFrames.toLong()).toInt()
            if (keepFrom > 0) {
                System.arraycopy(input, keepFrom * channels, input, 0, (inFrames - keepFrom) * channels)
                inFrames -= keepFrom
                base += keepFrom
            }
        }

        private fun flush() {
            if (outCount > 0) next.write(outBuf, outCount)
            outCount = 0
        }

        override fun finish() {
            if (!passthrough) produce(final = true)
            next.finish()
        }

        override fun close() = next.close()

        private fun gcd(a: Int, b: Int): Int = if (b == 0) a else gcd(b, a % b)

        companion object {
            private const val HALF = 16
            private const val TAPS = 2 * HALF
        }
    }
}
