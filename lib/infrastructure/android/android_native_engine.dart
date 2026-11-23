import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/download_destination.dart';
import '../../domain/models/download_progress.dart';
import '../../domain/models/media_info.dart';
import '../../domain/models/stream_option.dart';
import '../../domain/ports/media_engine_port.dart';
import '../desktop/desktop_process_engine.dart';

class AndroidNativeEngine implements IMediaEngine {
  static const MethodChannel _channel = MethodChannel('com.example.media_downloader/engine');
  static const EventChannel _eventChannel = EventChannel('com.example.media_downloader/download_progress');
  static const MethodChannel _folderChannel = MethodChannel('com.example.media_downloader/folder_picker');


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
    required DownloadDestination destination,
    String? customTitle,
  }) {
    final controller = StreamController<DownloadProgress>();

    void emit(DownloadProgress p) {
      if (!controller.isClosed) controller.add(p);
    }

    void finish() {
      _activeSubscription?.cancel();
      _activeSubscription = null;
      if (!controller.isClosed) controller.close();
    }

    emit(const DownloadProgress(
      status: DownloadStatus.downloading,
      percentage: 0.0,
      currentStep: 'Iniciando descarga en dispositivo móvil...',
    ));

    // yt-dlp descarga en una carpeta privada de la app y el lado nativo exporta el
    // archivo al destino (MediaStore o SAF), que resuelve también los nombres repetidos.
    final title = (customTitle == null || customTitle.trim().isEmpty) ? 'video' : customTitle.trim();
    final baseName =
        '${DesktopProcessEngine.sanitizeFilename(title)} [${DesktopProcessEngine.getQualityTag(option)}]';

    _activeSubscription?.cancel();
    _activeSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map) return;
        final status = switch (event['status']?.toString()) {
          'completed' => DownloadStatus.completed,
          'error' => DownloadStatus.error,
          'processing' => DownloadStatus.processing,
          _ => DownloadStatus.downloading,
        };

        emit(DownloadProgress(
          status: status,
          percentage: ((event['progress'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 100.0),
          speed: event['speed']?.toString(),
          eta: event['eta']?.toString(),
          currentStep: event['step']?.toString() ?? 'Descargando...',
          outputFilePath: event['filePath']?.toString(),
          outputUri: event['uri']?.toString(),
          errorMessage: status == DownloadStatus.error ? event['error']?.toString() : null,
        ));

        if (status == DownloadStatus.completed || status == DownloadStatus.error) {
          finish();
        }
      },
      onError: (err) {
        emit(DownloadProgress(status: DownloadStatus.error, errorMessage: err.toString()));
        finish();
      },
    );

    Future<void> start() async {
      // Android 7–9 necesita permiso para escribir en Download/ (desde Android 10 se usa MediaStore).
      if (destination.isAndroidDefault) {
        final granted = await _folderChannel.invokeMethod<bool>('ensureStoragePermission') ?? false;
        if (!granted) {
          throw PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'Se necesita permiso de almacenamiento para guardar en Descargas.',
          );
        }
      }
      await _channel.invokeMethod('download', {
        'url': url,
        'format': option.formatId,
        'isAudioOnly': option.isAudioOnly,
        'audioFormat': option.extension,
        'baseName': baseName,
        'treeUri': destination.androidTreeUri,
      });
    }

    start().catchError((Object err) {
      final message = err is PlatformException ? (err.message ?? err.code) : err.toString();
      emit(DownloadProgress(status: DownloadStatus.error, errorMessage: message));
      finish();
    });

    return controller.stream;
  }

  @override
  void cancel() {
    _channel.invokeMethod('cancelDownload');
    _activeSubscription?.cancel();
  }
}

