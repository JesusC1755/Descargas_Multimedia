import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/download_progress.dart';
import '../../domain/models/media_info.dart';
import '../../domain/models/stream_option.dart';
import '../../domain/ports/media_engine_port.dart';
import '../desktop/desktop_process_engine.dart';

class AndroidNativeEngine implements IMediaEngine {
  static const MethodChannel _channel = MethodChannel('com.example.media_downloader/engine');
  static const EventChannel _eventChannel = EventChannel('com.example.media_downloader/download_progress');

  /// En Android no se recodifica VP9/AV1 → H.264 (lento y costoso en batería),
  /// así que solo se ofrecen resoluciones con H.264 nativo, hasta 1080p.
  static const int maxVideoHeight = 1080;

  StreamSubscription? _activeSubscription;
  bool _isInit = false;
  bool _diagnosticsLogged = false;

  Future<bool> _ensureInitialized() async {
    if (_isInit) return true;
    try {
      // El lado nativo responde en cuanto yt-dlp/FFmpeg están listos y actualiza
      // yt-dlp en segundo plano (como máximo una vez cada 24 h).
      final success = await _channel.invokeMethod<bool>('init') ?? false;
      _isInit = success;
      return _isInit;
    } catch (e, st) {
      talker.error('Error inicializando motor nativo Android (youtubedl-android)', e, st);
      return false;
    }
  }

  @override
  Future<bool> isYtDlpAvailable() async {
    return _ensureInitialized();
  }

  @override
  Future<bool> isFFmpegAvailable() async {
    return _ensureInitialized();
  }

  @override
  Future<MediaInfo> analyzeUrl(String url) async {
    await _ensureInitialized();
    talker.info('AndroidNativeEngine: Analizando URL en motor nativo: $url');

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('analyzeUrl', {
        'url': url,
      });

      final debugLines = (result?['debug'] as List?)?.cast<String>() ?? const [];
      if (!_diagnosticsLogged && debugLines.isNotEmpty) {
        _diagnosticsLogged = true;
        talker.info('Diagnóstico yt-dlp (Android):\n${debugLines.join('\n')}');
      }
      final warnings = (result?['warnings'] as List?)?.cast<String>() ?? const [];
      for (final w in warnings) {
        talker.warning('[yt-dlp] $w');
      }

      final jsonString = result?['json'] as String?;
      if (jsonString == null || jsonString.isEmpty) {
        throw Exception('No se obtuvieron metadatos del contenido.');
      }

      final rawJson = jsonDecode(jsonString);
      if (rawJson is! Map<String, dynamic>) {
        throw Exception('Estructura de metadatos inesperada del motor móvil.');
      }

      return DesktopProcessEngine.parseMediaInfo(
        rawJson,
        url,
        h264Only: true,
        maxHeight: maxVideoHeight,
      );
    } catch (e, st) {
      talker.error('Error al analizar URL en Android', e, st);
      rethrow;
    }
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
      currentStep: 'Iniciando descarga en dispositivo móvil...',
    );
    controller.add(currentProgress);

    final expectedExt = option.isAudioOnly ? option.extension.toLowerCase().trim() : 'mp4';
    final normalizedDir = downloadDir.endsWith(Platform.pathSeparator)
        ? downloadDir.substring(0, downloadDir.length - 1)
        : downloadDir;

    final uniqueBaseName = DesktopProcessEngine.resolveOutputBaseName(
      customTitle: customTitle,
      option: option,
      downloadDir: normalizedDir,
    );

    final outputTemplate = '$normalizedDir${Platform.pathSeparator}$uniqueBaseName.%(ext)s';
    final expectedFinalPath = '$normalizedDir${Platform.pathSeparator}$uniqueBaseName.$expectedExt';

    _channel.invokeMethod('download', {
      'url': url,
      'outputPath': outputTemplate,
      'format': option.formatId,
      'isAudioOnly': option.isAudioOnly,
      'audioFormat': option.extension,
      'expectedFinalPath': expectedFinalPath,
    }).catchError((err) {
      controller.add(
        DownloadProgress(
          status: DownloadStatus.error,
          errorMessage: err.toString(),
        ),
      );
      controller.close();
    });

    _activeSubscription?.cancel();
    _activeSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          final statusStr = event['status']?.toString() ?? 'downloading';
          final progressVal = (event['progress'] as num?)?.toDouble() ?? 0.0;
          final speedStr = event['speed']?.toString();
          final etaStr = event['eta']?.toString();
          final currentStep = event['step']?.toString() ?? 'Descargando...';
          final filePath = event['filePath']?.toString();

          final status = switch (statusStr) {
            'completed' => DownloadStatus.completed,
            'error' => DownloadStatus.error,
            'processing' => DownloadStatus.processing,
            _ => DownloadStatus.downloading,
          };

          final progress = DownloadProgress(
            status: status,
            percentage: progressVal.clamp(0.0, 100.0),
            speed: speedStr,
            eta: etaStr,
            currentStep: currentStep,
            outputFilePath: filePath ?? (status == DownloadStatus.completed ? expectedFinalPath : null),
            errorMessage: status == DownloadStatus.error ? event['error']?.toString() : null,
          );

          controller.add(progress);
          if (status == DownloadStatus.completed || status == DownloadStatus.error) {
            _activeSubscription?.cancel();
            controller.close();
          }
        }
      },
      onError: (err) {
        controller.add(
          DownloadProgress(
            status: DownloadStatus.error,
            errorMessage: err.toString(),
          ),
        );
        controller.close();
      },
    );

    return controller.stream;
  }

  @override
  void cancel() {
    _channel.invokeMethod('cancelDownload');
    _activeSubscription?.cancel();
  }
}

