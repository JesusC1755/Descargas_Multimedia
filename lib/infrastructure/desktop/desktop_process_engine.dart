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
    talker.info('Iniciando análisis con $bin para URL: $url');
    final args = [
      '--js-runtimes', 'node',
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
      final rawJson = jsonDecode(process.stdout.toString()) as Map<String, dynamic>;

      final title = rawJson['title'] as String? ?? 'Sin título';
      final uploader = rawJson['uploader'] as String? ?? rawJson['channel'] as String?;
      final thumbnail = rawJson['thumbnail'] as String?;
      final duration = rawJson['duration'] as int?;

      final formats = rawJson['formats'] as List<dynamic>? ?? [];

      final Set<int> availableHeights = {};
      for (final f in formats) {
        if (f is Map<String, dynamic>) {
          final height = f['height'] as int?;
          final vcodec = f['vcodec'] as String?;
          if (height != null && height > 0 && vcodec != null && vcodec != 'none') {
            availableHeights.add(height);
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

        // Priorizamos H.264 (avc1) y audio AAC (mp4a) para máxima compatibilidad con todos los reproductores.
        // Si no existe (ej. 4K/2K donde YouTube solo tiene VP9/AV1), recurre a la mejor calidad disponible.
        final formatString = 'bestvideo[height<=$h][vcodec^=avc1]+bestaudio[acodec^=mp4a]'
            '/bestvideo[height<=$h][ext=mp4]+bestaudio[ext=m4a]'
            '/bestvideo[height<=$h]+bestaudio'
            '/best[height<=$h]/best';

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
            formatId: 'bestvideo[vcodec^=avc1]+bestaudio[acodec^=mp4a]/bestvideo+bestaudio/best',
            label: 'Mejor Calidad Disponible (MP4)',
            extension: 'mp4',
            isAudioOnly: false,
          ),
        );
      }

      final audioOptions = const <StreamOption>[
        StreamOption(
          formatId: 'bestaudio',
          label: 'MP3 (Máxima Calidad 320 kbps)',
          extension: 'mp3',
          isAudioOnly: true,
        ),
        StreamOption(
          formatId: 'bestaudio[ext=m4a]/bestaudio',
          label: 'M4A (AAC Original)',
          extension: 'm4a',
          isAudioOnly: true,
        ),
        StreamOption(
          formatId: 'bestaudio',
          label: 'FLAC (Lossless sin compresión)',
          extension: 'flac',
          isAudioOnly: true,
        ),
        StreamOption(
          formatId: 'bestaudio',
          label: 'Opus (Alta Fidelidad / Eficiente)',
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
    final args = <String>[
      '--js-runtimes', 'node',
      url,
      '--newline',
      '--progress-template',
      'download:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress._total_bytes_str)s',
      '-P',
      downloadDir,
      '-o',
      '%(title)s.%(ext)s',
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
        '--merge-output-format',
        'mp4',
      ]);
    }

    talker.info('Lanzando comando: $bin ${args.join(" ")}');
    final stderrBuffer = StringBuffer();

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
        } else if (line.contains('[Merger]') || line.contains('[ExtractAudio]') || line.contains('[Fixup')) {
          talker.info('[FFmpeg/Muxer] $line');
          currentProgress = currentProgress.copyWith(
            status: DownloadStatus.processing,
            percentage: 99.0,
            currentStep: 'Procesando y empaquetando con FFmpeg...',
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

      process.exitCode.then((code) {
        if (code == 0) {
          talker.info('Descarga finalizada con éxito (exitCode 0)');
          controller.add(
            currentProgress.copyWith(
              status: DownloadStatus.completed,
              percentage: 100.0,
              currentStep: '¡Descarga Exitosa!',
            ),
          );
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
        }
        controller.close();
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

  @override
  void cancel() {
    talker.warning('Cancelando proceso de descarga activo a petición del usuario.');
    _activeProcess?.kill(ProcessSignal.sigterm);
    _activeProcess = null;
  }
}
