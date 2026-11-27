package com.example.media_downloader

import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * Análisis de YouTube sin yt-dlp: una sola petición al API interno (`/youtubei/v1/player`) con el
 * cliente IOS_PRODUCER, el mismo que usa yt-dlp con `player_client=ios_producer`. YouTube responde
 * con URLs directas (sin desafío JS) en H.264 ≤1080p + AAC, también para música con licencia.
 * Tarda ~0,5 s porque no arranca Python. Si falla, se recurre a yt-dlp.
 *
 * Devuelve un JSON con la forma del `--dump-json` de yt-dlp, así Dart lo parsea igual.
 * Si YouTube rechaza la versión del cliente, actualizar las constantes con las de yt-dlp
 * (`yt_dlp/extractor/youtube/_base.py`, entrada `ios_producer`).
 */
object YouTubeFastExtractor {
    const val ENGINE = "fast"

    private const val CLIENT_NAME = "IOS_PRODUCER"
    private const val CLIENT_ID = "92"
    private const val CLIENT_VERSION = "0.147.945"
    private const val DEVICE_MODEL = "iPhone16,2"
    private const val OS_VERSION = "18.3.2.22D82"
    const val USER_AGENT =
        "com.google.ios.youtubeproducer/$CLIENT_VERSION ($DEVICE_MODEL; U; CPU iOS 18_3_2 like Mac OS X;)"

    private const val PLAYER_URL = "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"

    private val idPatterns = listOf(
        Regex("""^https?://(?:www\.|m\.|music\.)?youtube\.com/(?:watch\?(?:.*&)?v=|shorts/|live/|embed/|v/)([A-Za-z0-9_-]{11})"""),
        Regex("""^https?://(?:www\.)?youtu\.be/([A-Za-z0-9_-]{11})"""),
        Regex("""^https?://(?:www\.)?youtube-nocookie\.com/embed/([A-Za-z0-9_-]{11})"""),
    )

    private val codecsRegex = Regex("""codecs="([^"]*)"""")

    /** Id del vídeo si [url] es de YouTube; null para cualquier otro sitio. */
    fun videoIdOf(url: String): String? =
        idPatterns.firstNotNullOfOrNull { it.find(url.trim())?.groupValues?.get(1) }

    fun analyze(videoId: String): String {
        val response = JSONObject(post(requestBody(videoId)))

        val playability = response.optJSONObject("playabilityStatus")
        val status = playability?.optString("status")
        if (status != "OK") {
            throw IOException("YouTube respondió $status: ${playability?.optString("reason")}")
        }
        val details = response.optJSONObject("videoDetails")
            ?: throw IOException("Respuesta sin videoDetails")
        if (details.optString("videoId") != videoId) throw IOException("La respuesta es de otro vídeo")
        // Los directos solo llegan por HLS: de eso se encarga yt-dlp.
        if (details.optBoolean("isLive") || details.optBoolean("isUpcoming")) {
            throw IOException("Directo o estreno: se usa yt-dlp")
        }

        val streaming = response.optJSONObject("streamingData")
            ?: throw IOException("Respuesta sin streamingData")
        val formats = JSONArray()
        for (key in listOf("formats", "adaptiveFormats")) {
            val list = streaming.optJSONArray(key) ?: continue
            for (i in 0 until list.length()) {
                list.optJSONObject(i)?.let(::toFormat)?.let(formats::put)
            }
        }
        val all = (0 until formats.length()).map { formats.getJSONObject(it) }
        if (all.none { it.getString("vcodec").startsWith("avc1") } || all.none { it.getString("vcodec") == "none" }) {
            throw IOException("Sin formatos H.264 + audio con URL directa")
        }

        return JSONObject()
            .put("_engine", ENGINE)
            .put("extractor", "youtube")
            .put("id", videoId)
            .put("webpage_url", "https://www.youtube.com/watch?v=$videoId")
            .put("title", details.optString("title"))
            .put("uploader", details.optString("author"))
            .put("channel", details.optString("author"))
            .put("thumbnail", bestThumbnail(details, videoId))
            .put("duration", details.optString("lengthSeconds").toLongOrNull() ?: 0L)
            .put("formats", formats)
            .toString()
    }

    private fun requestBody(videoId: String): String = JSONObject()
        .put(
            "context", JSONObject().put(
                "client", JSONObject()
                    .put("clientName", CLIENT_NAME)
                    .put("clientVersion", CLIENT_VERSION)
                    .put("deviceMake", "Apple")
                    .put("deviceModel", DEVICE_MODEL)
                    .put("userAgent", USER_AGENT)
                    .put("osName", "iPhone")
                    .put("osVersion", OS_VERSION)
                    .put("hl", "en")
                    .put("timeZone", "UTC")
                    .put("utcOffsetMinutes", 0)
            )
        )
        .put("videoId", videoId)
        .put(
            "playbackContext", JSONObject().put(
                "contentPlaybackContext", JSONObject().put("html5Preference", "HTML5_PREF_WANTS")
            )
        )
        .put("contentCheckOk", true)
        .put("racyCheckOk", true)
        .toString()

    private fun post(body: String): String {
        val connection = URL(PLAYER_URL).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 10_000
            connection.readTimeout = 15_000
            connection.doOutput = true
            connection.setRequestProperty("User-Agent", USER_AGENT)
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("X-Youtube-Client-Name", CLIENT_ID)
            connection.setRequestProperty("X-Youtube-Client-Version", CLIENT_VERSION)
            connection.setRequestProperty("Origin", "https://www.youtube.com")
            connection.outputStream.use { it.write(body.toByteArray()) }
            val code = connection.responseCode
            if (code != HttpURLConnection.HTTP_OK) throw IOException("HTTP $code del API de YouTube")
            return connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }

    /** Convierte un formato del API al estilo de yt-dlp. Null si no trae URL directa. */
    private fun toFormat(f: JSONObject): JSONObject? {
        val url = f.optString("url").takeIf { it.isNotEmpty() } ?: return null
        if (f.optBoolean("isDrc")) return null
        val mime = f.optString("mimeType")
        val type = mime.substringBefore(';').trim()
        val codecs = codecsRegex.find(mime)?.groupValues?.get(1)
            ?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }
            ?: return null
        val isVideo = type.startsWith("video/")
        val container = type.substringAfter('/')
        val ext = when {
            container == "mp4" && !isVideo -> "m4a"
            else -> container
        }
        val out = JSONObject()
            .put("format_id", f.optInt("itag").toString())
            .put("url", url)
            .put("ext", ext)
            .put("protocol", "https")
            .put("vcodec", if (isVideo) codecs[0] else "none")
            .put("acodec", if (isVideo) codecs.getOrNull(1) ?: "none" else codecs[0])
            .put("format_note", f.optString("qualityLabel").ifEmpty { f.optString("audioQuality") })
        f.optString("contentLength").toLongOrNull()?.let { out.put("filesize", it) }
        if (f.has("bitrate")) out.put("tbr", f.optLong("bitrate") / 1000.0)
        if (isVideo) {
            out.put("width", f.optInt("width"))
            out.put("height", f.optInt("height"))
            if (f.has("fps")) out.put("fps", f.optInt("fps"))
        } else {
            f.optString("audioSampleRate").toIntOrNull()?.let { out.put("asr", it) }
            if (f.has("audioChannels")) out.put("audio_channels", f.optInt("audioChannels"))
            // Vídeos doblados: varias pistas de audio; se marca la original.
            val track = f.optJSONObject("audioTrack")
            out.put("audio_is_default", track?.optBoolean("audioIsDefault") ?: true)
        }
        return out
    }

    private fun bestThumbnail(details: JSONObject, videoId: String): String {
        val list = details.optJSONObject("thumbnail")?.optJSONArray("thumbnails")
        val best = (0 until (list?.length() ?: 0))
            .mapNotNull { list?.optJSONObject(it) }
            .maxByOrNull { it.optInt("width") * it.optInt("height") }
            ?.optString("url")
        return best?.takeIf { it.isNotEmpty() } ?: "https://i.ytimg.com/vi/$videoId/hqdefault.jpg"
    }
}
