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

  String _getYtDlpExecutable() {
    final home = Platform.environment['HOME'] ?? '';
    final localBin = '$home/.local/bin/yt-dlp';
    if (File(localBin).existsSync()) {
      return localBin;
    }
    const usrLocalBin = '/usr/local/bin/yt-dlp';
    if (File(usrLocalBin).existsSync()) {
      return usrLocalBin;
    }
    return 'yt-dlp';
  }

  List<String> _getJsRuntimeArgs() {
    final home = Platform.environment['HOME'] ?? '';
    final nodeBin = '$home/.local/bin/node';
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
    try {
      final res = await Process.run('ffmpeg', ['-version']);
      final available = res.exitCode == 0;
      if (available) {
        talker.info('FFmpeg detectado correctamente en el sistema.');
      } else {
        talker.warning('FFmpeg no está accesible.');
      }
      return available;
    } catch (e, st) {
      talker.error('Error al verificar FFmpeg en el sistema', e, st);
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

      final title = rawJson['title']?.toString() ?? 'Sin título';
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

  @override
  Stream<DownloadProgress> download({
    required String url,
    required StreamOption option,
    required String downloadDir,
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
    final args = <String>[
      ...jsArgs,
      url,
      '--newline',
      '--progress-template',
      'download:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress._total_bytes_str)s',
      '-P',
      downloadDir,
      '-o',
      '%(title)s.%(ext)s',
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
      final probeResult = await Process.run('ffprobe', [
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

      final transcodeProcess = await Process.start('ffmpeg', ffmpegArgs);
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
    _activeProcess?.kill(ProcessSignal.sigterm);
    _activeProcess = null;
    _activeTranscodeProcess?.kill(ProcessSignal.sigterm);
    _activeTranscodeProcess = null;
  }
}
