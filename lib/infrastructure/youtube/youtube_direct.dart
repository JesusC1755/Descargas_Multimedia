import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Análisis de YouTube sin yt-dlp: una sola petición al API interno (`/youtubei/v1/player`) con
/// el cliente IOS_PRODUCER, el mismo que usa yt-dlp con `player_client=ios_producer`. YouTube
/// responde con URLs directas (sin desafío JS) en H.264 ≤1080p + AAC, también para música con
/// licencia, en ~0,5 s. Si falla, el motor recurre a yt-dlp.
///
/// Es la versión en Dart de `YouTubeFastExtractor.kt` (Android). Si YouTube rechaza la versión del
/// cliente, actualizar las constantes de ambos con las de yt-dlp
/// (`yt_dlp/extractor/youtube/_base.py`, entrada `ios_producer`).
class YouTubeDirectClient {
  static const String engine = 'fast';

  static const String _clientName = 'IOS_PRODUCER';
  static const String _clientId = '92';
  static const String _clientVersion = '0.147.945';
  static const String _deviceModel = 'iPhone16,2';
  static const String _osVersion = '18.3.2.22D82';
  static const String userAgent =
      'com.google.ios.youtubeproducer/$_clientVersion ($_deviceModel; U; CPU iOS 18_3_2 like Mac OS X;)';

  static final Uri _playerUri = Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

  static final List<RegExp> _idPatterns = [
    RegExp(r'^https?://(?:www\.|m\.|music\.)?youtube\.com/(?:watch\?(?:.*&)?v=|shorts/|live/|embed/|v/)([A-Za-z0-9_-]{11})'),
    RegExp(r'^https?://(?:www\.)?youtu\.be/([A-Za-z0-9_-]{11})'),
    RegExp(r'^https?://(?:www\.)?youtube-nocookie\.com/embed/([A-Za-z0-9_-]{11})'),
  ];

  static final RegExp _codecsRegex = RegExp(r'codecs="([^"]*)"');

  /// Id del vídeo si [url] es de YouTube; null para cualquier otro sitio.
  static String? videoIdOf(String url) {
    for (final pattern in _idPatterns) {
      final match = pattern.firstMatch(url.trim());
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// Devuelve un mapa con la forma del `--dump-json` de yt-dlp (más `_engine`).
  static Future<Map<String, dynamic>> analyze(String videoId) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(_playerUri);
      request.headers
        ..set(HttpHeaders.userAgentHeader, userAgent)
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set('X-Youtube-Client-Name', _clientId)
        ..set('X-Youtube-Client-Version', _clientVersion)
        ..set('Origin', 'https://www.youtube.com');
      request.add(utf8.encode(jsonEncode(_requestBody(videoId))));
      final response = await request.close().timeout(const Duration(seconds: 15));
      final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode} del API de YouTube');
      }
      return parsePlayerResponse(jsonDecode(body) as Map<String, dynamic>, videoId);
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic> _requestBody(String videoId) => {
        'context': {
          'client': {
            'clientName': _clientName,
            'clientVersion': _clientVersion,
            'deviceMake': 'Apple',
            'deviceModel': _deviceModel,
            'userAgent': userAgent,
            'osName': 'iPhone',
            'osVersion': _osVersion,
            'hl': 'en',
            'timeZone': 'UTC',
            'utcOffsetMinutes': 0,
          },
        },
        'videoId': videoId,
        'playbackContext': {
          'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'},
        },
        'contentCheckOk': true,
        'racyCheckOk': true,
      };

  /// Convierte la respuesta del API al formato de yt-dlp. Lanza si no sirve para descargar.
  @visibleForTesting
  static Map<String, dynamic> parsePlayerResponse(Map<String, dynamic> response, String videoId) {
    final playability = response['playabilityStatus'] as Map<String, dynamic>?;
    final status = playability?['status'];
    if (status != 'OK') {
      throw StateError('YouTube respondió $status: ${playability?['reason']}');
    }
    final details = response['videoDetails'] as Map<String, dynamic>?;
    if (details == null) throw StateError('Respuesta sin videoDetails');
    if (details['videoId'] != videoId) throw StateError('La respuesta es de otro vídeo');
    // Los directos solo llegan por HLS: de eso se encarga yt-dlp.
    if (details['isLive'] == true || details['isUpcoming'] == true) {
      throw StateError('Directo o estreno: se usa yt-dlp');
    }
    final streaming = response['streamingData'] as Map<String, dynamic>?;
    if (streaming == null) throw StateError('Respuesta sin streamingData');

    final formats = <Map<String, dynamic>?>[
      for (final key in const ['formats', 'adaptiveFormats'])
        for (final f in (streaming[key] as List? ?? const []))
          if (f is Map<String, dynamic>) _toFormat(f),
    ].whereType<Map<String, dynamic>>().toList();
    final hasVideo = formats.any((f) => (f['vcodec'] as String).startsWith('avc1'));
    final hasAudio = formats.any((f) => f['vcodec'] == 'none');
    if (!hasVideo || !hasAudio) throw StateError('Sin formatos H.264 + audio con URL directa');

    return {
      '_engine': engine,
      'extractor': 'youtube',
      'id': videoId,
      'webpage_url': 'https://www.youtube.com/watch?v=$videoId',
      'title': details['title'] ?? '',
      'uploader': details['author'] ?? '',
      'channel': details['author'] ?? '',
      'thumbnail': _bestThumbnail(details, videoId),
      'duration': int.tryParse('${details['lengthSeconds']}') ?? 0,
      'formats': formats,
    };
  }

  static Map<String, dynamic>? _toFormat(Map<String, dynamic> f) {
    final url = f['url'] as String?;
    if (url == null || url.isEmpty || f['isDrc'] == true) return null;
    final mime = f['mimeType'] as String? ?? '';
    final type = mime.split(';').first.trim();
    final codecs = (_codecsRegex.firstMatch(mime)?.group(1) ?? '')
        .split(',')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    if (codecs.isEmpty) return null;
    final isVideo = type.startsWith('video/');
    final container = type.contains('/') ? type.split('/').last : type;
    final bitrate = f['bitrate'] as num?;
    final size = int.tryParse('${f['contentLength']}');
    final sampleRate = int.tryParse('${f['audioSampleRate']}');
    final track = f['audioTrack'] as Map<String, dynamic>?;
    return {
      'format_id': '${f['itag']}',
      'url': url,
      'ext': container == 'mp4' && !isVideo ? 'm4a' : container,
      'protocol': 'https',
      'vcodec': isVideo ? codecs[0] : 'none',
      'acodec': isVideo ? (codecs.length > 1 ? codecs[1] : 'none') : codecs[0],
      'format_note': (f['qualityLabel'] as String?) ?? (f['audioQuality'] as String?) ?? '',
      if (size != null) 'filesize': size,
      if (bitrate != null) 'tbr': bitrate / 1000,
      if (isVideo) ...{
        'width': f['width'],
        'height': f['height'],
        if (f['fps'] != null) 'fps': f['fps'],
      } else ...{
        if (sampleRate != null) 'asr': sampleRate,
        if (f['audioChannels'] != null) 'audio_channels': f['audioChannels'],
        // Vídeos doblados: varias pistas de audio; se marca la original.
        'audio_is_default': track?['audioIsDefault'] ?? true,
      },
    };
  }

  static String _bestThumbnail(Map<String, dynamic> details, String videoId) {
    final list = ((details['thumbnail'] as Map?)?['thumbnails'] as List?)?.whereType<Map>().toList() ?? const [];
    Map? best;
    var bestArea = -1;
    for (final t in list) {
      final area = ((t['width'] as num?) ?? 0) * ((t['height'] as num?) ?? 0);
      if (area > bestArea) {
        bestArea = area.toInt();
        best = t;
      }
    }
    final url = best?['url'] as String?;
    return (url == null || url.isEmpty) ? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg' : url;
  }

  /// Elige las pistas a descargar: AAC (la original si está doblado) y, para vídeo, el H.264
  /// de mayor resolución que no supere [height] (resolución = lado menor, como en `parseMediaInfo`).
  static ({Map<String, dynamic> audio, Map<String, dynamic>? video}) pickFormats(
    Map<String, dynamic> info, {
    required bool audioOnly,
    int? height,
  }) {
    final formats = (info['formats'] as List).cast<Map<String, dynamic>>();
    final audios = formats
        .where((f) => f['vcodec'] == 'none' && '${f['acodec']}'.startsWith('mp4a'))
        .toList()
      ..sort((a, b) {
        final byDefault = ((b['audio_is_default'] ?? true) ? 1 : 0) - ((a['audio_is_default'] ?? true) ? 1 : 0);
        if (byDefault != 0) return byDefault;
        return ((b['tbr'] as num?) ?? 0).compareTo((a['tbr'] as num?) ?? 0);
      });
    if (audios.isEmpty) throw StateError('Sin pista de audio AAC');
    if (audioOnly) return (audio: audios.first, video: null);

    int res(Map<String, dynamic> f) {
      final w = (f['width'] as num?)?.toInt() ?? 0;
      final h = (f['height'] as num?)?.toInt() ?? 0;
      return w < h ? w : h;
    }

    final target = (height == null || height <= 0) ? 1080 : height;
    final videos = formats.where((f) => '${f['vcodec']}'.startsWith('avc1') && f['acodec'] == 'none').toList()
      ..sort((a, b) {
        final byRes = res(b).compareTo(res(a));
        if (byRes != 0) return byRes;
        return ((b['tbr'] as num?) ?? 0).compareTo((a['tbr'] as num?) ?? 0);
      });
    if (videos.isEmpty) throw StateError('Sin pista de vídeo H.264');
    final video = videos.firstWhere((f) => res(f) <= target, orElse: () => videos.last);
    return (audio: audios.first, video: video);
  }
}

/// Descarga HTTP directa de las URLs de [YouTubeDirectClient]: bloques de 10 MB con `Range`
/// (YouTube limita las peticiones sin rango) repartidos entre varias conexiones, de modo que
/// vídeo y audio se bajan a la vez. Cada bloque se reintenta desde donde se cortó.
class DirectHttpDownloader {
  static const int _chunkSize = 10 * 1024 * 1024;
  static const int _connections = 4;
  static const int _maxRetries = 4;

  final String userAgent;
  final bool Function() isCancelled;

  DirectHttpDownloader({required this.userAgent, required this.isCancelled});

  int _downloaded = 0;

  /// [onProgress] recibe bytes descargados, total (0 si se desconoce) y bytes/s.
  Future<void> download(
    List<({String url, File dest, int size})> parts,
    void Function(int downloaded, int total, double bytesPerSecond) onProgress,
  ) async {
    final queue = <({String url, File dest, int start, int end})>[];
    for (final part in parts) {
      await part.dest.parent.create(recursive: true);
      if (part.size > 0) {
        final raf = await part.dest.open(mode: FileMode.write);
        await raf.truncate(part.size);
        await raf.close();
        for (var start = 0; start < part.size; start += _chunkSize) {
          final end = (start + _chunkSize < part.size ? start + _chunkSize : part.size) - 1;
          queue.add((url: part.url, dest: part.dest, start: start, end: end));
        }
      } else {
        await part.dest.writeAsBytes(const []);
        queue.add((url: part.url, dest: part.dest, start: 0, end: -1));
      }
    }
    final total = parts.every((p) => p.size > 0) ? parts.fold<int>(0, (sum, p) => sum + p.size) : 0;

    var lastBytes = 0;
    var lastAt = DateTime.now();
    var speed = 0.0;
    final timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final now = DateTime.now();
      final elapsed = now.difference(lastAt).inMicroseconds;
      final instant = (_downloaded - lastBytes) * 1e6 / (elapsed <= 0 ? 1 : elapsed);
      speed = speed == 0 ? instant : speed * 0.7 + instant * 0.3;
      lastBytes = _downloaded;
      lastAt = now;
      onProgress(_downloaded, total, speed);
    });

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = userAgent;
    try {
      var next = 0;
      Future<void> worker() async {
        while (next < queue.length) {
          final chunk = queue[next++];
          await _fetchWithRetries(client, chunk);
        }
      }

      await Future.wait([for (var i = 0; i < _connections; i++) worker()]);
    } finally {
      timer.cancel();
      client.close(force: true);
    }
    onProgress(_downloaded, total, 0);
  }

  Future<void> _fetchWithRetries(
    HttpClient client,
    ({String url, File dest, int start, int end}) chunk,
  ) async {
    var from = chunk.start;
    var attempt = 0;
    while (true) {
      _checkCancelled();
      try {
        from += await _fetch(client, chunk, from);
        if (chunk.end < 0 || from > chunk.end) return;
        throw const HttpException('Conexión cerrada antes de tiempo');
      } on DownloadCancelledException {
        rethrow;
      } on Exception catch (e) {
        if (++attempt > _maxRetries) throw HttpException('Fallo al descargar: $e');
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
  }

  /// Descarga desde [from] hasta el final del bloque; devuelve los bytes escritos.
  Future<int> _fetch(HttpClient client, ({String url, File dest, int start, int end}) chunk, int from) async {
    var written = 0;
    RandomAccessFile? raf;
    try {
      final request = await client.getUrl(Uri.parse(chunk.url));
      final ranged = chunk.end >= 0 || from > 0;
      if (ranged) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-${chunk.end >= 0 ? chunk.end : ''}');
      final response = await request.close().timeout(const Duration(seconds: 20));
      final expected = ranged ? HttpStatus.partialContent : HttpStatus.ok;
      if (response.statusCode != expected) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}');
      }
      raf = await chunk.dest.open(mode: FileMode.append);
      await raf.setPosition(from);
      await for (final data in response.timeout(const Duration(seconds: 20))) {
        _checkCancelled();
        await raf.writeFrom(data);
        written += data.length;
        _downloaded += data.length;
      }
      return written;
    } on DownloadCancelledException {
      rethrow;
    } on Exception {
      // Lo ya escrito vale: el reintento continúa desde ahí.
      if (written > 0) return written;
      rethrow;
    } finally {
      await raf?.close();
    }
  }

  void _checkCancelled() {
    if (isCancelled()) throw const DownloadCancelledException();
  }
}

class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => 'Descarga cancelada';
}
