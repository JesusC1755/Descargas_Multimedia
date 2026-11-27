package com.example.media_downloader

/** Codificador MP3 (LAME 3.100, compilado en `src/main/cpp`). */
object Mp3Encoder {
    init {
        System.loadLibrary("mp3lame_jni")
    }

    /** [vbrQuality]: 0 = máxima calidad VBR (equivale a `--audio-quality 0` de yt-dlp). Devuelve 0 si falla. */
    @JvmStatic external fun nativeInit(sampleRate: Int, channels: Int, vbrQuality: Int): Long

    @JvmStatic external fun nativeEncode(handle: Long, pcm: ShortArray, samplesPerChannel: Int, out: ByteArray): Int

    @JvmStatic external fun nativeFlush(handle: Long, out: ByteArray): Int

    @JvmStatic external fun nativeLameTag(handle: Long, out: ByteArray): Int

    @JvmStatic external fun nativeClose(handle: Long)
}
