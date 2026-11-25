import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/download_destination.dart';
import '../../domain/models/download_progress.dart';
import '../../domain/models/media_info.dart';
import '../../domain/models/stream_option.dart';
import '../../domain/ports/media_engine_port.dart';

class DesktopProcessEngine implements IMediaEngine {
  Process? _activeProcess;
  bool _cancelRequested = false;

  static final RegExp _emojiRegex = RegExp(
    r'[\u{1F600}-\u{1F64F}' // Emoticons
    r'\u{1F300}-\u{1F5FF}' // Misc Symbols and Pictographs (🎦, 🔥, etc.)
    r'\u{1F680}-\u{1F6FF}' // Transport and Map
    r'\u{1F1E0}-\u{1F1FF}' // Flags
    r'\u{1F900}-\u{1F9FF}' // Supplemental Symbols and Pictographs (🤯, etc.)
    r'\u{1FA70}-\u{1FAFF}' // Symbols and Pictographs Extended-A
    r'\u{1F780}-\u{1F7FF}' // Geometric Shapes Extended
    r'\u{2600}-\u{26FF}'   // Misc Symbols (⚡, ☕, ⚠️, ❤️, etc.)
    r'\u{2700}-\u{27BF}'   // Dingbats (✨, ❌, etc.)
    r'\u{2300}-\u{23FF}'   // Misc Technical (⌚, ⌛, etc.)
    r'\u{2B50}\u{2B55}'    // Stars, circles
    r'\u{25AA}-\u{25FE}'   // Geometric shapes
    r'\u{2934}\u{2935}'    // Arrows
    r'\u{200D}'            // ZWJ
    r'\u{FE00}-\u{FE0F}'   // Variation selectors
    r'\u{E0020}-\u{E007F}' // Tags
    r'\u{20E3}'            // Combining enclosing keycap
    r']+',
    unicode: true,
  );

  static final RegExp emojiRegex = _emojiRegex;

  static const String _progressMarker = '[PROGRESS]';

  // --- Caché del análisis ---------------------------------------------------------------
  // La descarga reutiliza el JSON del análisis con `--load-info-json` y no repite la
  // extracción (~8 s menos en YouTube). Los enlaces de YouTube caducan a las ~6 h; 3 h deja margen.

  static const Duration _infoTtl = Duration(hours: 3);
  final Map<String, ({File file, DateTime savedAt})> _infoCache = {};
  int _infoCounter = 0;

  Directory get _infoDir => Directory('${Directory.systemTemp.path}${Platform.pathSeparator}media_downloader_info');

  void _saveInfo(String url, String json) {
    try {
      _discardInfo(url);
      _infoDir.createSync(recursive: true);
      // Restos de sesiones anteriores ya caducados.
      for (final old in _infoDir.listSync().whereType<File>()) {
        if (DateTime.now().difference(old.statSync().modified) > _infoTtl) old.deleteSync();
      }
      final file = File('${_infoDir.path}${Platform.pathSeparator}${pid}_${_infoCounter++}.json');
      file.writeAsStringSync(json);
      _infoCache[url] = (file: file, savedAt: DateTime.now());
    } catch (e) {
      // Sin caché la descarga simplemente vuelve a extraer desde la URL.
      talker.warning('No se pudo guardar el análisis para reutilizarlo: $e');
    }
  }

  File? _cachedInfoFor(String url) {
    final entry = _infoCache[url];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.savedAt) > _infoTtl || !entry.file.existsSync()) {
      _discardInfo(url);
      return null;
    }
    return entry.file;
  }

  void _discardInfo(String url) {
    final entry = _infoCache.remove(url);
    try {
      entry?.file.deleteSync();
    } catch (_) {}
  }

  String _resolveToolExecutable(String baseName) {
    final isWin = Platform.isWindows;
    final exeName = isWin ? '$baseName.exe' : baseName;

    // 1. Prioridad: Buscar en la carpeta tools/ o bin/ empaquetada junto al ejecutable
    try {
      final appDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        '$appDir${Platform.pathSeparator}tools${Platform.pathSeparator}$exeName',
        '$appDir${Platform.pathSeparator}bin${Platform.pathSeparator}$exeName',
        '$appDir${Platform.pathSeparator}$exeName',
      ];
      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          return candidate;
        }
      }
    } catch (_) {}

    // 2. Rutas estándar conocidas en Linux / Unix
    if (!isWin) {
      final home = Platform.environment['HOME'] ?? '';
      final localBin = '$home/.local/bin/$exeName';
      if (File(localBin).existsSync()) return localBin;

      final usrLocalBin = '/usr/local/bin/$exeName';
      if (File(usrLocalBin).existsSync()) return usrLocalBin;

      final usrBin = '/usr/bin/$exeName';
      if (File(usrBin).existsSync()) return usrBin;
    }

    // 3. Fallback al nombre del binario para resolución mediante el PATH del sistema
    return exeName;
  }

  String _getYtDlpExecutable() => _resolveToolExecutable('yt-dlp');
  String _getFfmpegExecutable() => _resolveToolExecutable('ffmpeg');
  String _getNodeExecutable() => _resolveToolExecutable('node');

  List<String> _getJsRuntimeArgs() {
    final nodeBin = _getNodeExecutable();
    if (File(nodeBin).existsSync()) {
      return ['--js-runtimes', 'node:$nodeBin'];
    }
    return ['--js-runtimes', 'node'];
  }

  @override
  Future<bool> isYtDlpAvailable() async {
    final bin = _getYtDlpExecutable();
    try {
      final res = await Process.run(bin, ['--version']);
      final available = res.exitCode == 0;
      if (available) {
        talker.info('yt-dlp ($bin) versión: ${res.stdout.toString().trim()}');
        unawaited(_updateYtDlpIfDue(bin));
      } else {
        talker.warning('yt-dlp falló con código ${res.exitCode}: ${res.stderr}');
      }
      return available;
    } catch (e, st) {
      talker.error('Error al verificar yt-dlp ($bin) en el sistema', e, st);
      return false;
    }
  }

  static const String _lastUpdateKey = 'ytdlp_last_update_ms';
  static const Duration _updateInterval = Duration(hours: 24);

  /// Actualiza yt-dlp (`yt-dlp -U`, canal estable) en segundo plano si pasaron 24 h desde
  /// el último intento, como en Android: YouTube cambia a menudo y un yt-dlp viejo deja de
  /// funcionar. Solo funciona con el binario oficial en una ruta con permiso de escritura
  /// (ej. `~/.local/bin`); instalado con pacman/pip o en Docker, yt-dlp lo rechaza y solo
  /// queda registrado. En Linux/Windows el binario se reemplaza sin afectar a procesos en curso.
  Future<void> _updateYtDlpIfDue(String bin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = prefs.getInt(_lastUpdateKey) ?? 0;
      if (now - last < _updateInterval.inMilliseconds) return;
      await prefs.setInt(_lastUpdateKey, now);

      final res = await Process.run(bin, ['-U']).timeout(const Duration(minutes: 2));
      final output = '${res.stdout}\n${res.stderr}'.trim();
      if (res.exitCode == 0) {
        talker.info('Actualización de yt-dlp: $output');
      } else {
        talker.warning('yt-dlp no se pudo actualizar (código ${res.exitCode}): $output');
      }
    } catch (e) {
      talker.warning('Error al actualizar yt-dlp: $e');
    }
  }

  @override
  Future<bool> isFFmpegAvailable() async {
    final bin = _getFfmpegExecutable();
    try {
      final res = await Process.run(bin, ['-version']);
      final available = res.exitCode == 0;
      if (available) {
        talker.info('FFmpeg ($bin) detectado correctamente en el sistema.');
      } else {
        talker.warning('FFmpeg falló con código ${res.exitCode}: ${res.stderr}');
      }
      return available;
    } catch (e, st) {
      talker.error('Error al verificar FFmpeg ($bin) en el sistema', e, st);
      return false;
    }
  }

  /// Calidades ofrecidas: H.264 hasta 1080p, que se descarga sin recodificar
  /// (por encima de 1080p YouTube solo entrega VP9/AV1).
  static const int maxVideoHeight = 1080;

  /// Cliente de YouTube (`youtube:player_client=…`): analiza en ~4 s frente a ~8 s de los
  /// clientes por defecto y descarga más rápido. Si falla, se reintenta con los de yt-dlp.
  static const String youtubePlayerClient = 'ios_producer';

  @override
  Future<MediaInfo> analyzeUrl(String url) async {
    final bin = _getYtDlpExecutable();
    final jsArgs = _getJsRuntimeArgs();
    talker.info('Iniciando análisis con $bin para URL: $url');
    List<String> argsFor(String? playerClient) => [
          ...jsArgs,
          '--no-playlist',
          '--dump-json',
          if (playerClient != null) ...['--extractor-args', 'youtube:player_client=$playerClient'],
          url,
        ];

    var process = await Process.run(bin, argsFor(youtubePlayerClient));
    if (process.exitCode != 0) {
      talker.warning('Análisis con $youtubePlayerClient falló; reintentando con los clientes por defecto', process.stderr);
      process = await Process.run(bin, argsFor(null));
    }

    if (process.exitCode != 0) {
      final err = process.stderr.toString().trim();
      talker.error('yt-dlp falló al analizar URL (código ${process.exitCode})', err);
      throw Exception(err.isNotEmpty ? err : 'Error desconocido al analizar URL');
    }

    try {
      final rawJson = jsonDecode(process.stdout.toString());
      if (rawJson is! Map<String, dynamic>) {
        throw Exception('Estructura de metadatos inesperada de yt-dlp');
      }

      _saveInfo(url, process.stdout.toString());
      return parseMediaInfo(rawJson, url, h264Only: true, maxHeight: maxVideoHeight);
    } catch (e, st) {
      talker.error('Error parseando JSON de metadatos de yt-dlp', e, st);
      rethrow;
    }
  }

  /// Parsea el mapa de metadatos JSON generado por yt-dlp y construye el modelo inmutable [MediaInfo].
  ///
  /// - [h264Only]: solo ofrece resoluciones que existan en H.264 (avc1/h264). Los formatos
  ///   cuyo códec se desconoce (ej. progresivos de Facebook) se conservan. Se usa en Android,
  ///   donde no se recodifica VP9/AV1 a H.264 para no gastar batería.
  /// - [maxHeight]: descarta resoluciones por encima de este valor (ej. 1080 en Android).
  static MediaInfo parseMediaInfo(
    Map<String, dynamic> rawJson,
    String url, {
    bool h264Only = false,
    int? maxHeight,
  }) {
    final rawTitle = rawJson['title']?.toString() ?? 'Sin título';
    final title = sanitizeTitle(rawTitle);
    final uploader = (rawJson['uploader'] ?? rawJson['channel'] ?? rawJson['creator'] ?? rawJson['artist'])?.toString();
    final thumbnail = rawJson['thumbnail']?.toString();
    final duration = (rawJson['duration'] as num?)?.round();

    final formats = rawJson['formats'] as List<dynamic>? ?? [];

    final Set<int> availableHeights = {};
    for (final f in formats) {
      if (f is Map) {
        final vcodec = f['vcodec']?.toString();
        if (vcodec == 'none') continue; // Omitir streams de solo audio
        if (h264Only && !_isH264OrUnknown(vcodec)) continue;

        int? width = (f['width'] as num?)?.toInt();
        int? height = (f['height'] as num?)?.toInt();

        // Si el extractor no incluye dimensiones directamente (común en Facebook SD/HD, Vimeo, etc.),
        // inferir a partir de resolution, format_note o format_id
        if (height == null || height <= 0 || width == null || width <= 0) {
          final res = f['resolution']?.toString() ?? '';
          final match = RegExp(r'(\d+)x(\d+)').firstMatch(res);
          if (match != null) {
            width ??= int.tryParse(match.group(1)!);
            height ??= int.tryParse(match.group(2)!);
          }
        }

        // Para videos verticales (ej. 1080x1920 en Reels/Shorts), el estándar visual es el lado menor (1080p).
        // Para videos horizontales (ej. 1920x1080), también es el lado menor (1080p).
        int? standardRes;
        if (width != null && height != null && width > 0 && height > 0) {
          standardRes = width < height ? width : height;
        } else {
          standardRes = height;
        }

        if (standardRes == null || standardRes <= 0) {
          final note = (f['format_note']?.toString() ?? f['format_id']?.toString() ?? '').toLowerCase();
          if (note.contains('4k') || note.contains('2160')) {
            standardRes = 2160;
          } else if (note.contains('2k') || note.contains('1440')) {
            standardRes = 1440;
          } else if (note.contains('1080') || note.contains('fhd')) {
            standardRes = 1080;
          } else if (note.contains('720') || note == 'hd' || note.contains('hd')) {
            standardRes = 720;
          } else if (note.contains('480') || note == 'sd' || note.contains('sd')) {
            standardRes = 480;
          } else if (note.contains('360')) {
            standardRes = 360;
          }
        }

        if (standardRes != null && standardRes > 0 && (maxHeight == null || standardRes <= maxHeight)) {
          availableHeights.add(standardRes);
        }
      }
    }

    // YouTube expone a veces formatos residuales (ej. 72p) que no aportan nada al usuario.
    if (availableHeights.any((h) => h >= 144)) {
      availableHeights.removeWhere((h) => h < 144);
    }

    final sortedHeights = availableHeights.toList()..sort((a, b) => b.compareTo(a));

    final videoOptions = <StreamOption>[];
    for (final h in sortedHeights) {
      String label = '${h}p';
      if (h >= 2160) {
        label = '4K ($label)';
      } else if (h >= 1440) {
        label = '2K QHD ($label)';
      } else if (h >= 1080) {
        label = 'Full HD ($label)';
      } else if (h >= 720) {
        label = 'HD ($label)';
      }

      videoOptions.add(
        StreamOption(
          formatId: buildVideoFormatSelector(height: h, h264Only: h264Only),
          label: label,
          extension: 'mp4',
          height: h,
          isAudioOnly: false,
        ),
      );
    }

    if (videoOptions.isEmpty) {
      videoOptions.add(
        StreamOption(
          formatId: buildVideoFormatSelector(height: null, h264Only: h264Only),
          label: 'Mejor Calidad Disponible (MP4)',
          extension: 'mp4',
          isAudioOnly: false,
        ),
      );
    }

    // M4A y Opus se guardan tal como los entrega la plataforma (sin recodificar);
    // MP3 y FLAC se convierten con FFmpeg, más lento y sin ganar calidad.
    final audioOptions = const <StreamOption>[
      StreamOption(
        formatId: 'bestaudio[ext=m4a]/bestaudio',
        label: 'M4A',
        extension: 'm4a',
        note: 'Recomendado',
        isAudioOnly: true,
      ),
      StreamOption(
        formatId: 'bestaudio',
        label: 'MP3',
        extension: 'mp3',
        note: 'Compatible',
        isAudioOnly: true,
      ),
      StreamOption(
        formatId: 'bestaudio[acodec=opus]/bestaudio',
        label: 'Opus',
        extension: 'opus',
        note: 'Ligero',
        isAudioOnly: true,
      ),
      StreamOption(
        formatId: 'bestaudio',
        label: 'FLAC',
        extension: 'flac',
        note: 'Para edición',
        isAudioOnly: true,
      ),
    ];

    talker.info('Análisis completado: "$title" (${videoOptions.length} calidades de video)');

    return MediaInfo(
      url: url,
      title: title,
      uploader: uploader,
      thumbnailUrl: thumbnail,
      durationSeconds: duration,
      videoOptions: videoOptions,
      audioOptions: audioOptions,
    );
  }

  static bool _isH264OrUnknown(String? vcodec) {
    if (vcodec == null || vcodec.trim().isEmpty) return true;
    final c = vcodec.toLowerCase();
    return c.startsWith('avc') || c.contains('h264');
  }

  /// Construye la cadena `-f` de yt-dlp para una altura dada ([height] nulo = mejor disponible).
  ///
  /// Siempre se prioriza H.264 (avc1/h264) + AAC (mp4a) para reproducción universal.
  /// - Escritorio ([h264Only] = false): si la plataforma solo ofrece VP9/AV1 a esa altura
  ///   se descarga igualmente y el motor la recodifica a H.264 al finalizar.
  /// - Android ([h264Only] = true): nunca se eligen VP9/AV1; solo H.264, progresivos con
  ///   códec desconocido u otros códecs reproducibles sin recodificar.
  @visibleForTesting
  static String buildVideoFormatSelector({required int? height, required bool h264Only}) {
    // Cota máxima para admitir tanto orientaciones horizontales (16:9) como verticales (9:16)
    final maxDim = height == null ? null : (height * 16 / 9).round() + 20;
    final dim = maxDim == null ? '' : '[height<=$maxDim][width<=$maxDim]';
    final dimOrUnknown = maxDim == null ? '' : '[height<=?$maxDim][width<=?$maxDim]';

    final parts = <String>[
      // 1. Pistas separadas con H.264 nativo + audio AAC nativo
      'bv*$dim[vcodec^=avc1]+ba[acodec^=mp4a]',
      'bv*$dim[vcodec^=avc1]+ba',
      'bv*$dim[vcodec*=h264]+ba[acodec*=aac]',
      'bv*$dim[vcodec*=h264]+ba',
      // 2. Formatos progresivos universales (ej. Facebook HD/SD)
      if (height == null || height >= 720) 'b[format_id=hd]',
      if (height == null || height <= 480) 'b[format_id=sd]',
      'b$dim[vcodec^=avc1]',
      'b$dim[vcodec*=h264]',
      // 3. Fallbacks
      if (h264Only) ...[
        'b$dimOrUnknown[vcodec!*=?vp][vcodec!*=?av01][vcodec!=?none]',
        'b',
      ] else ...[
        // Máxima calidad disponible (se recodificará a H.264 al concluir)
        'bv*$dim+ba[acodec^=mp4a]',
        'bv*$dim+ba',
        'b$dim[vcodec!=none]',
        'bv*+ba',
        'b[vcodec!=none]',
      ],
    ];
    // LinkedHashSet elimina duplicados conservando el orden de prioridad.
    return parts.toSet().join('/');
  }

  static String sanitizeTitle(String rawTitle) {
    var cleaned = rawTitle.trim();

    // 1. Elimina prefijos típicos de métricas en Facebook / Reels / redes sociales:
    // Ej: "7.4K views · 265 reactions |", "13K views · 900 reactions ｜"
    cleaned = cleaned.replaceFirst(
      RegExp(
        r'^[\d\.,]+[kKmMbB]?\s*(?:views?|reproducciones|visualizaciones)\s*[·•|\-—\uff5c]\s*[\d\.,]+[kKmMbB]?\s*(?:reactions?|reacciones|likes|me gusta)\s*[·•|\-—\uff5c]\s*',
        caseSensitive: false,
      ),
      '',
    );

    // 2. Elimina hashtags (#animereels, #anime, #luffy, etc.)
    cleaned = cleaned.replaceAll(
      RegExp(r'#[\w\u00C0-\u017F\d_]+', caseSensitive: false),
      '',
    );

    // 3. Elimina emojis y símbolos gráficos
    cleaned = cleaned.replaceAll(_emojiRegex, '');

    // 4. Elimina sufijo de página o canal al final tras limpiar hashtags (ej. "| Cad.mons" o "｜ Dioses del Fandom")
    cleaned = cleaned.replaceFirst(
      RegExp(r'\s*[|｜]\s*[\w\s\.\-_]{1,30}\s*$', caseSensitive: false),
      '',
    );

    // 5. Colapsa espacios múltiples y recorta extremos
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 6. Elimina separadores colgantes al inicio o al final
    cleaned = cleaned.replaceAll(RegExp(r'^[|｜\s]+|[|｜\s]+$'), '').trim();

    return cleaned.isNotEmpty ? cleaned : rawTitle;
  }

  /// Limpia un título para usarlo como nombre de archivo (compartido con Android).
  static String sanitizeFilename(String title, {int maxLength = 160}) {
    var safe = title.replaceAll(_emojiRegex, '');
    safe = safe.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    safe = safe.replaceAll(RegExp(r'\s+'), ' ').trim();
    safe = safe.replaceAll(RegExp(r'[. ]+$'), '');
    if (safe.length > maxLength) {
      safe = safe.substring(0, maxLength).trim();
    }
    return safe.isNotEmpty ? safe : 'video';
  }

  /// Genera una etiqueta corta y limpia para el nombre de archivo (ej. [1080p], [720p], [MP3], [M4A]).
  static String getQualityTag(StreamOption option) {
    if (option.isAudioOnly) {
      final label = option.label
          .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F\[\]]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return label.isNotEmpty ? label : option.extension.toUpperCase();
    }

    if (option.height != null && option.height! > 0) {
      return '${option.height}p';
    }

    if (option.label.toLowerCase().contains('mejor')) {
      return 'Mejor Calidad';
    }

    final cleanLabel = option.label
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F\[\]]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleanLabel.isNotEmpty ? cleanLabel : 'Video';
  }

  /// Resuelve el nombre base del archivo asegurando que incluya la calidad/formato
  /// y previniendo colisiones mediante sufijo incremental (1), (2), etc. si el archivo ya existe.
  @visibleForTesting
  static String resolveOutputBaseName({
    required String? customTitle,
    required StreamOption option,
    required String downloadDir,
  }) {
    final qualityTag = getQualityTag(option);
    if (customTitle == null || customTitle.trim().isEmpty) {
      return '%(title)s [$qualityTag]';
    }

    final baseTitle = sanitizeFilename(customTitle.trim());
    final titleWithQuality = '$baseTitle [$qualityTag]';
    final expectedExt = option.isAudioOnly ? option.extension.toLowerCase().trim() : 'mp4';

    final normalizedDir = downloadDir.endsWith(Platform.pathSeparator)
        ? downloadDir.substring(0, downloadDir.length - 1)
        : downloadDir;

    String uniqueBaseName = titleWithQuality;
    final targetFile = File('$normalizedDir${Platform.pathSeparator}$uniqueBaseName.$expectedExt');
    if (targetFile.existsSync()) {
      int counter = 1;
      while (File('$normalizedDir${Platform.pathSeparator}$uniqueBaseName ($counter).$expectedExt').existsSync()) {
        counter++;
      }
      uniqueBaseName = '$uniqueBaseName ($counter)';
    }

    return uniqueBaseName;
  }

  @override
  Stream<DownloadProgress> download({
    required String url,
    required StreamOption option,
    required DownloadDestination destination,
    String? customTitle,
  }) {
    final downloadDir = destination.displayPath;
    final controller = StreamController<DownloadProgress>();
    _cancelRequested = false;
    DownloadProgress currentProgress = const DownloadProgress(
      status: DownloadStatus.downloading,
      percentage: 0.0,
      currentStep: 'Iniciando proceso de descarga...',
    );
    controller.add(currentProgress);

    final bin = _getYtDlpExecutable();
    final jsArgs = _getJsRuntimeArgs();

    final expectedExt = option.isAudioOnly ? option.extension.toLowerCase().trim() : 'mp4';
    final normalizedDir = downloadDir.endsWith(Platform.pathSeparator)
        ? downloadDir.substring(0, downloadDir.length - 1)
        : downloadDir;

    final uniqueBaseName = resolveOutputBaseName(
      customTitle: customTitle,
      option: option,
      downloadDir: normalizedDir,
    );

    final outputTemplate = '$uniqueBaseName.%(ext)s';
    final expectedFinalPath = (customTitle != null && customTitle.trim().isNotEmpty)
        ? '$normalizedDir${Platform.pathSeparator}$uniqueBaseName.$expectedExt'
        : null;

    final args = <String>[
      ...jsArgs,
      '--newline',
      // Limpieza de métricas en metadatos
      '--replace-in-metadata',
      'title',
      r'^[\d\.,]+[kKmMbB]?\s*(?:views?|reproducciones|visualizaciones)\s*[·•|\-—\uff5c]\s*[\d\.,]+[kKmMbB]?\s*(?:reactions?|reacciones|likes|me gusta)\s*[·•|\-—\uff5c]\s*',
      '',
      // Limpieza de hashtags en metadatos
      '--replace-in-metadata',
      'title',
      r'#[\w\u00C0-\u017F\d_]+',
      '',
      // Limpieza de emojis en metadatos
      '--replace-in-metadata',
      'title',
      r'[\U0001F300-\U0001FAFF\U00002600-\U000027BF\U00002300-\U000023FF\U00002B50-\U00002B55]',
      '',
      // --print implica --quiet, que oculta el progreso; --progress lo vuelve a mostrar.
      '--progress',
      // "download:" es el TIPO de plantilla (no se imprime); "[PROGRESS]" es el marcador que se parsea.
      '--progress-template',
      'download:$_progressMarker%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress._total_bytes_str)s',
      '-P',
      downloadDir,
      '-o',
      outputTemplate,
      '--print',
      'after_move:[FINAL_PATH]:%(filepath)s',
    ];

    if (option.isAudioOnly) {
      args.addAll([
        // Sin -f, yt-dlp toma el mejor audio (Opus en YouTube) y luego lo recodifica.
        // Con el selector de la opción, M4A y Opus se descargan ya en su códec.
        '-f',
        option.formatId,
        '-x',
        '--audio-format',
        option.extension,
        '--audio-quality',
        '0',
      ]);
    } else {
      args.addAll([
        '-f',
        option.formatId,
        '-S',
        // `proto`: a igual resolución, HTTPS antes que HLS (m3u8 baja en fragmentos, más lento).
        'vcodec:h264,res,proto,acodec:aac',
        '--merge-output-format',
        'mp4',
        '--remux-video',
        'mp4',
      ]);
    }

    final ffmpegBin = _getFfmpegExecutable();
    final ffmpegDir = File(ffmpegBin).existsSync() ? File(ffmpegBin).parent.path : null;
    if (ffmpegDir != null) {
      args.addAll(['--ffmpeg-location', ffmpegDir]);
    }

    // Con el JSON del análisis no se repite la extracción; si falla (enlaces caducados u
    // otro error), se reintenta una vez desde la URL.
    final cachedInfo = _cachedInfoFor(url);

    void launch({required bool fromInfo}) {
      final source = fromInfo ? ['--load-info-json', cachedInfo!.path] : [url];
      final fullArgs = [...source, ...args];
      talker.info('Lanzando comando: $bin ${fullArgs.join(" ")}');
      final stderrBuffer = StringBuffer();
      String? downloadedFilePath;

      Process.start(bin, fullArgs).then((process) {
        _activeProcess = process;

        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          if (line.startsWith(_progressMarker)) {
            final parts = line.substring(_progressMarker.length).split('|');
            if (parts.isNotEmpty) {
              final rawPercent = parts[0].replaceAll('%', '').trim();
              final percent = double.tryParse(rawPercent) ?? currentProgress.percentage;
              final speed = parts.length > 1 ? parts[1].trim() : null;
              final eta = parts.length > 2 ? parts[2].trim() : null;

              currentProgress = currentProgress.copyWith(
                status: DownloadStatus.downloading,
                percentage: percent,
                speed: speed,
                eta: eta,
                currentStep: 'Descargando flujo de medios...',
              );
              controller.add(currentProgress);
            }
          } else if (line.startsWith('[FINAL_PATH]:')) {
            final path = line.substring(13).trim();
            if (path.isNotEmpty) {
              downloadedFilePath = path;
              talker.info('Ruta final detectada vía [FINAL_PATH]: $downloadedFilePath');
            }
          } else if (line.contains('[Merger] Merging formats into "')) {
            final match = RegExp(r'\[Merger\] Merging formats into "([^"]+)"').firstMatch(line);
            if (match != null) {
              downloadedFilePath ??= match.group(1);
            }
            talker.info('[FFmpeg/Muxer] $line');
            currentProgress = currentProgress.copyWith(
              status: DownloadStatus.processing,
              percentage: 99.0,
              currentStep: 'Empaquetando pistas con FFmpeg...',
            );
            controller.add(currentProgress);
          } else if (line.contains('Destination: ')) {
            final match = RegExp(r'Destination:\s+(.+\.(?:mp4|mkv|webm|m4a|mp3|flac|opus))').firstMatch(line);
            if (match != null) {
              downloadedFilePath ??= match.group(1);
            }
          } else if (line.contains('[ExtractAudio]') || line.contains('[Fixup')) {
            talker.info('[FFmpeg/Muxer] $line');
            currentProgress = currentProgress.copyWith(
              status: DownloadStatus.processing,
              percentage: 99.0,
              currentStep: 'Procesando audio con FFmpeg...',
            );
            controller.add(currentProgress);
          } else if (line.trim().isNotEmpty) {
            talker.debug('[yt-dlp stdout] $line');
          }
        });

        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          if (line.trim().isNotEmpty) {
            stderrBuffer.writeln(line);
            talker.warning('[yt-dlp stderr] $line');
          }
        });

        process.exitCode.then((code) async {
          _activeProcess = null;
          if (code == 0) {
            downloadedFilePath ??= (expectedFinalPath != null && File(expectedFinalPath).existsSync())
                ? expectedFinalPath
                : null;

            talker.info('Descarga finalizada con éxito (exitCode 0)');
            controller.add(
              currentProgress.copyWith(
                status: DownloadStatus.completed,
                percentage: 100.0,
                currentStep: '¡Descarga Exitosa!',
                outputFilePath: downloadedFilePath,
              ),
            );
            controller.close();
          } else if (_cancelRequested) {
            talker.info('Descarga cancelada por el usuario (exitCode $code)');
            controller.add(
              currentProgress.copyWith(status: DownloadStatus.cancelled, currentStep: 'Descarga cancelada'),
            );
            controller.close();
          } else if (fromInfo) {
            talker.warning('Fallo con el análisis guardado (código $code); reintentando desde la URL', stderrBuffer.toString().trim());
            _discardInfo(url);
            currentProgress = currentProgress.copyWith(percentage: 0.0, currentStep: 'Reintentando descarga...');
            controller.add(currentProgress);
            launch(fromInfo: false);
          } else {
            final errorMsg = stderrBuffer.toString().trim();
            final formattedError = errorMsg.isNotEmpty
                ? errorMsg
                : 'El proceso yt-dlp finalizó con código de error: $code';

            talker.error('Descarga fallida (exitCode $code)', formattedError);
            controller.add(
              currentProgress.copyWith(
                status: DownloadStatus.error,
                errorMessage: formattedError,
              ),
            );
            controller.close();
          }
        });
      }).catchError((err, st) {
        talker.error('Excepción al invocar subproceso de yt-dlp', err, st);
        controller.add(
          DownloadProgress(
            status: DownloadStatus.error,
            errorMessage: 'No se pudo iniciar el proceso de descarga: $err',
          ),
        );
        controller.close();
      });
    }

    launch(fromInfo: cachedInfo != null);
    return controller.stream;
  }

  @override
  void cancel() {
    talker.warning('Cancelando proceso de descarga activo a petición del usuario.');
    _cancelRequested = true;
    try {
      _activeProcess?.kill();
    } catch (e) {
      talker.warning('Error al cancelar _activeProcess: $e');
    }
    _activeProcess = null;
  }
}
