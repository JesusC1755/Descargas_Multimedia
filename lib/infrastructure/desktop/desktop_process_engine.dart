import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/models/download_progress.dart';
import '../../domain/models/media_info.dart';
import '../../domain/models/stream_option.dart';
import '../../domain/ports/media_engine_port.dart';

class DesktopProcessEngine implements IMediaEngine {
  Process? _activeProcess;

  @override
  Future<bool> isYtDlpAvailable() async {
    try {
      final res = await Process.run('yt-dlp', ['--version']);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isFFmpegAvailable() async {
    try {
      final res = await Process.run('ffmpeg', ['-version']);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<MediaInfo> analyzeUrl(String url) async {
    final process = await Process.run(
      'yt-dlp',
      ['--no-playlist', '--dump-json', url],
    );

    if (process.exitCode != 0) {
      final err = process.stderr.toString();
      throw Exception('Error al analizar URL con yt-dlp: $err');
    }

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

      videoOptions.add(
        StreamOption(
          formatId: 'bestvideo[height<=$h]+bestaudio/best[height<=$h]/best',
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
          formatId: 'bestvideo+bestaudio/best',
          label: 'Mejor Calidad Disponible',
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
      currentStep: 'Iniciando descarga...',
    );
    controller.add(currentProgress);

    final args = <String>[
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

    Process.start('yt-dlp', args).then((process) {
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
          currentProgress = currentProgress.copyWith(
            status: DownloadStatus.processing,
            percentage: 99.0,
            currentStep: 'Procesando y empaquetando con FFmpeg...',
          );
          controller.add(currentProgress);
        }
      });

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        // Logging opcional
      });

      process.exitCode.then((code) {
        if (code == 0) {
          controller.add(
            currentProgress.copyWith(
              status: DownloadStatus.completed,
              percentage: 100.0,
              currentStep: '¡Descarga y procesado completados con éxito!',
            ),
          );
        } else {
          controller.add(
            currentProgress.copyWith(
              status: DownloadStatus.error,
              errorMessage: 'El proceso finalizó con código de error: $code',
            ),
          );
        }
        controller.close();
      });
    }).catchError((err) {
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
    _activeProcess?.kill(ProcessSignal.sigterm);
    _activeProcess = null;
  }
}
