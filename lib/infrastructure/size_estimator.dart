/// Peso de un archivo: exacto si la plataforma lo da, o aproximado (bitrate × duración).
typedef EstimatedSize = ({int bytes, bool approx});

/// Calcula cuánto pesará cada opción de descarga a partir de los formatos de yt-dlp
/// (o del camino directo de YouTube, que usa los mismos campos).
class SizeEstimator {
  /// LAME V0 (Android) y `-q:a 0` (escritorio) rondan los 245 kbps.
  static const int mp3Kbps = 245;

  /// Bitrate de Opus al convertir en Android (MediaTools).
  static const int opusKbps = 128;

  /// FLAC de audio con pérdida decodificado: orientativo.
  static const int flacKbps = 900;

  final List<Map> _formats;
  final int? _duration;

  SizeEstimator(this._formats, this._duration);

  EstimatedSize? sizeOf(Map f) {
    final exact = (f['filesize'] as num?)?.toInt();
    if (exact != null && exact > 0) return (bytes: exact, approx: false);
    final approx = (f['filesize_approx'] as num?)?.toInt();
    if (approx != null && approx > 0) return (bytes: approx, approx: true);
    final tbr = f['tbr'] as num?;
    if (tbr == null || tbr <= 0) return null;
    return atBitrate(tbr);
  }

  /// [kbps] × duración. Null si no se conoce la duración.
  EstimatedSize? atBitrate(num kbps) {
    final duration = _duration;
    if (duration == null || duration <= 0) return null;
    return (bytes: (kbps * 1000 / 8 * duration).round(), approx: true);
  }

  /// La pista de audio que se descarga: AAC primero, la original si el video está doblado
  /// y la de mayor bitrate (como `YouTubeDirectClient.pickFormats`).
  EstimatedSize? bestAudio() {
    final audios = _formats.where(_isAudioOnly).toList()
      ..sort((a, b) {
        final byAac = _isAac(b).compareTo(_isAac(a));
        if (byAac != 0) return byAac;
        final byDefault = _flag(b['audio_is_default']).compareTo(_flag(a['audio_is_default']));
        if (byDefault != 0) return byDefault;
        return _tbr(b).compareTo(_tbr(a));
      });
    return audios.isEmpty ? null : sizeOf(audios.first);
  }

  /// La pista Opus original, que se guarda sin recodificar cuando existe.
  EstimatedSize? opusAudio() {
    final opus = _formats.where((f) => _isAudioOnly(f) && '${f['acodec']}'.startsWith('opus')).toList()
      ..sort((a, b) => _tbr(b).compareTo(_tbr(a)));
    return opus.isEmpty ? null : sizeOf(opus.first);
  }

  /// Video de una resolución: H.264 primero y el de mayor bitrate; más el audio si va aparte.
  EstimatedSize? video(List<Map> candidates) {
    if (candidates.isEmpty) return null;
    final sorted = [...candidates]..sort((a, b) {
        final byH264 = _isH264(b).compareTo(_isH264(a));
        if (byH264 != 0) return byH264;
        return _tbr(b).compareTo(_tbr(a));
      });
    final picked = sorted.first;
    final videoSize = sizeOf(picked);
    if (videoSize == null) return null;
    if (picked['acodec'] != 'none') return videoSize;

    final audioSize = bestAudio();
    if (audioSize == null) return null;
    return (bytes: videoSize.bytes + audioSize.bytes, approx: videoSize.approx || audioSize.approx);
  }

  static bool _isAudioOnly(Map f) => f['vcodec'] == 'none' && f['acodec'] != null && f['acodec'] != 'none';
  static int _isAac(Map f) => '${f['acodec']}'.startsWith('mp4a') ? 1 : 0;
  static int _isH264(Map f) {
    final c = '${f['vcodec']}'.toLowerCase();
    return c.startsWith('avc') || c.contains('h264') ? 1 : 0;
  }

  static int _flag(Object? value) => value == false ? 0 : 1;
  static num _tbr(Map f) => (f['tbr'] as num?) ?? 0;
}
