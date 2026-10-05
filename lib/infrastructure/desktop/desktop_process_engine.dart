import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/logging/app_logger.dart';
import '../../domain/models/download_progress.dart';
import '../../domain/models/media_info.dart';
import '../../domain/models/stream_option.dart';
import '../../domain/ports/media_engine_port.dart';

class DesktopProcessEngine implements IMediaEngine {
  Process? _activeProcess;
  Process? _activeTranscodeProcess;

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
  String _getFfprobeExecutable() => _resolveToolExecutable('ffprobe');
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
      } else {
        talker.warning('yt-dlp falló con código ${res.exitCode}: ${res.stderr}');
      }
      return available;
    } catch (e, st) {
      talker.error('Error al verificar yt-dlp ($bin) en el sistema', e, st);
      return false;
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

  @override
  Future<MediaInfo> analyzeUrl(String url) async {
    final bin = _getYtDlpExecutable();
    final jsArgs = _getJsRuntimeArgs();
    talker.info('Iniciando análisis con $bin para URL: $url');
    final args = [
      ...jsArgs,
      '--no-playlist',
      '--dump-json',
      url,
    ];

    final process = await Process.run(bin, args);

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

      final rawTitle = rawJson['title']?.toString() ?? 'Sin título';
      final title = _sanitizeTitle(rawTitle);
      final uploader = (rawJson['uploader'] ?? rawJson['channel'] ?? rawJson['creator'] ?? rawJson['artist'])?.toString();
      final thumbnail = rawJson['thumbnail']?.toString();
      final duration = (rawJson['duration'] as num?)?.round();

      final formats = rawJson['formats'] as List<dynamic>? ?? [];

      final Set<int> availableHeights = {};
      for (final f in formats) {
        if (f is Map) {
          final vcodec = f['vcodec']?.toString();
          if (vcodec == 'none') continue; // Omitir streams de solo audio

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

          if (standardRes != null && standardRes > 0) {
            availableHeights.add(standardRes);
          }
        }
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

        // Cota máxima para admitir tanto orientaciones horizontales (16:9) como verticales (9:16)
        final maxDim = (h * 16 / 9).round() + 20;

        // Priorizamos H.264 (avc1/h264) y audio AAC (mp4a/aac) para reproducción universal en VLC.
        // Si la plataforma (ej. Facebook 1080p) solo dispone de AV1 o VP9, recurrimos a ella
        // y nuestro motor la transcodificará automáticamente a H.264 al concluir la descarga.
        final formatParts = <String>[
          // 1. Separate streams con códec H.264 nativo + audio AAC nativo
          'bv*[height<=$maxDim][width<=$maxDim][vcodec^=avc1]+ba[acodec^=mp4a]',
          'bv*[height<=$maxDim][width<=$maxDim][vcodec^=avc1]+ba',
          'bv*[height<=$maxDim][width<=$maxDim][vcodec*=h264]+ba[acodec*=aac]',
          'bv*[height<=$maxDim][width<=$maxDim][vcodec*=h264]+ba',
          // 2. Formatos progresivos universales nativos (ej. Facebook HD/SD)
          if (h >= 720) 'b[format_id=hd]',
          if (h <= 480) 'b[format_id=sd]',
          'b[height<=$maxDim][width<=$maxDim][vcodec^=avc1]',
          'b[height<=$maxDim][width<=$maxDim][vcodec*=h264]',
          // 3. Fallbacks de la máxima calidad disponible (se transcodificará automáticamente a H.264)
          'bv*[height<=$maxDim][width<=$maxDim]+ba[acodec^=mp4a]',
          'bv*[height<=$maxDim][width<=$maxDim]+ba',
          'b[height<=$maxDim][width<=$maxDim][vcodec!=none]',
          'bv*+ba',
          'b[vcodec!=none]',
        ];
        final formatString = formatParts.join('/');

        videoOptions.add(
          StreamOption(
            formatId: formatString,
            label: label,
            extension: 'mp4',
            height: h,
            isAudioOnly: false,
          ),
        );
      }

      if (videoOptions.isEmpty) {
        videoOptions.add(
          const StreamOption(
            formatId: 'bv*[vcodec^=avc1]+ba[acodec^=mp4a]'
                '/bv*[vcodec^=avc1]+ba'
                '/bv*[vcodec*=h264]+ba[acodec*=aac]'
                '/bv*[vcodec*=h264]+ba'
                '/b[format_id=hd]'
                '/b[format_id=sd]'
                '/b[vcodec^=avc1]'
                '/b[vcodec*=h264]'
                '/bv*+ba'
                '/b[vcodec!=none]',
            label: 'Mejor Calidad Disponible (MP4)',
            extension: 'mp4',
            isAudioOnly: false,
          ),
        );
      }

      final audioOptions = const <StreamOption>[
        StreamOption(
          formatId: 'bestaudio',
          label: 'MP3',
          extension: 'mp3',
          isAudioOnly: true,
        ),
        StreamOption(
          formatId: 'bestaudio[ext=m4a]/bestaudio',
          label: 'M4A',
          extension: 'm4a',
          isAudioOnly: true,
        ),
        StreamOption(
          formatId: 'bestaudio',
          label: 'FLAC',
          extension: 'flac',
          isAudioOnly: true,
        ),
        StreamOption(
          formatId: 'bestaudio',
          label: 'Opus',
          extension: 'opus',
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
    } catch (e, st) {
      talker.error('Error parseando JSON de metadatos de yt-dlp', e, st);
      rethrow;
    }
  }

  String _sanitizeTitle(String rawTitle) {
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

  String _sanitizeFilename(String title) {
    var safe = title.replaceAll(_emojiRegex, '');
    safe = safe.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    safe = safe.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (safe.length > 180) {
      safe = safe.substring(0, 180).trim();
    }
    return safe.isNotEmpty ? safe : 'video';
  }

  @override
  Stream<DownloadProgress> download({
    required String url,
    required StreamOption option,
    required String downloadDir,
    String? customTitle,
  }) {
    final controller = StreamController<DownloadProgress>();
    DownloadProgress currentProgress = const DownloadProgress(
      status: DownloadStatus.downloading,
      percentage: 0.0,
      currentStep: 'Iniciando proceso de descarga...',
    );
    controller.add(currentProgress);

    final bin = _getYtDlpExecutable();
    final jsArgs = _getJsRuntimeArgs();

    final outputTemplate = (customTitle != null && customTitle.trim().isNotEmpty)
        ? '${_sanitizeFilename(customTitle.trim())}.%(ext)s'
        : '%(title)s.%(ext)s';

    final args = <String>[
      ...jsArgs,
      url,
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
      '--progress-template',
      'download:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress._total_bytes_str)s',
      '-P',
      downloadDir,
      '-o',
      outputTemplate,
      '--print',
      'after_move:[FINAL_PATH]:%(filepath)s',
    ];

    if (option.isAudioOnly) {
      args.addAll([
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
        'vcodec:h264,res,acodec:aac',
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

    talker.info('Lanzando comando: $bin ${args.join(" ")}');
    final stderrBuffer = StringBuffer();
    String? downloadedFilePath;

    Process.start(bin, args).then((process) {
      _activeProcess = process;

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.startsWith('download:')) {
          final parts = line.substring(9).split('|');
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
          if (!option.isAudioOnly && downloadedFilePath != null && File(downloadedFilePath!).existsSync()) {
            await _ensureH264Compatibility(
              downloadedFilePath!,
              controller,
              currentProgress,
            );
          } else {
            talker.info('Descarga finalizada con éxito (exitCode 0)');
            controller.add(
              currentProgress.copyWith(
                status: DownloadStatus.completed,
                percentage: 100.0,
                currentStep: '¡Descarga Exitosa!',
              ),
            );
            controller.close();
          }
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

    return controller.stream;
  }

  /// Verifica el códec del video descargado con ffprobe.
  /// Si el códec es AV1 (av01), VP9 u otro que cause fallos en VLC/aceleración por hardware,
  /// transcodifica la pista de video a H.264 (AVC) preservando el audio original AAC intacto (-c:a copy).
  Future<void> _ensureH264Compatibility(
    String filePath,
    StreamController<DownloadProgress> controller,
    DownloadProgress currentProgress,
  ) async {
    try {
      final ffprobeBin = _getFfprobeExecutable();
      final probeResult = await Process.run(ffprobeBin, [
        '-v', 'error',
        '-select_streams', 'v:0',
        '-show_entries', 'stream=codec_name',
        '-of', 'default=noprint_wrappers=1:nokey=1',
        filePath,
      ]);

      final codec = probeResult.stdout.toString().trim().toLowerCase();
      talker.info('Códec de video detectado en "$filePath": $codec');

      // Si ya es H.264 / AVC, es 100% compatible y universal en VLC
      if (codec == 'h264' || codec == 'avc1') {
        talker.info('El video ya utiliza códec universal H.264.');
        controller.add(
          currentProgress.copyWith(
            status: DownloadStatus.completed,
            percentage: 100.0,
            currentStep: '¡Descarga Exitosa!',
          ),
        );
        controller.close();
        return;
      }

      talker.warning('Códec no universal detectado ($codec). Optimizando a H.264 para reproducción garantizada en VLC...');
      controller.add(
        currentProgress.copyWith(
          status: DownloadStatus.processing,
          percentage: 99.0,
          currentStep: 'Optimizando códec a H.264 (Universal para VLC)...',
        ),
      );

      final tempPath = '$filePath.h264.mp4';
      final ffmpegArgs = [
        '-y',
        '-i', filePath,
        '-c:v', 'libx264',
        '-preset', 'veryfast',
        '-crf', '21',
        '-pix_fmt', 'yuv420p',
        '-c:a', 'copy',
        tempPath,
      ];

      final ffmpegBin = _getFfmpegExecutable();
      final transcodeProcess = await Process.start(ffmpegBin, ffmpegArgs);
      _activeTranscodeProcess = transcodeProcess;

      final transcodeExit = await transcodeProcess.exitCode;
      _activeTranscodeProcess = null;

      if (transcodeExit == 0 && File(tempPath).existsSync()) {
        final originalFile = File(filePath);
        final tempFile = File(tempPath);
        originalFile.deleteSync();
        tempFile.renameSync(filePath);
        talker.info('Optimización a H.264 completada con éxito.');
        controller.add(
          currentProgress.copyWith(
            status: DownloadStatus.completed,
            percentage: 100.0,
            currentStep: '¡Descarga Exitosa! (Optimizado a H.264)',
          ),
        );
      } else {
        talker.warning('Transcodificación a H.264 retornó código $transcodeExit. Se conserva el archivo original.');
        if (File(tempPath).existsSync()) {
          try {
            File(tempPath).deleteSync();
          } catch (_) {}
        }
        controller.add(
          currentProgress.copyWith(
            status: DownloadStatus.completed,
            percentage: 100.0,
            currentStep: '¡Descarga Exitosa!',
          ),
        );
      }
    } catch (e, st) {
      talker.error('Error durante la verificación/optimización de códec H.264', e, st);
      controller.add(
        currentProgress.copyWith(
          status: DownloadStatus.completed,
          percentage: 100.0,
          currentStep: '¡Descarga Exitosa!',
        ),
      );
    } finally {
      controller.close();
    }
  }

  @override
  void cancel() {
    talker.warning('Cancelando proceso de descarga activo a petición del usuario.');
    try {
      _activeProcess?.kill();
    } catch (e) {
      talker.warning('Error al cancelar _activeProcess: $e');
    }
    _activeProcess = null;
    try {
      _activeTranscodeProcess?.kill();
    } catch (e) {
      talker.warning('Error al cancelar _activeTranscodeProcess: $e');
    }
    _activeTranscodeProcess = null;
  }
}
