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

  /// Cliente de YouTube que usa yt-dlp en Android (`youtube:player_client=…`).
  /// `ios_producer` no exige el desafío JavaScript que el teléfono resuelve con QuickJS
  /// (~10 s de análisis frente a ~52 s), sirve también para música con licencia (que
  /// `visionos` rechaza) y no limita la velocidad por conexión (~9 MB/s). Si falla, el lado
  /// nativo reintenta con los clientes por defecto de yt-dlp.
  static const String youtubePlayerClient = 'ios_producer';

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
      final stopwatch = Stopwatch()..start();
      final result = await _channel.invokeMapMethod<String, dynamic>('analyzeUrl', {
        'url': url,
        'playerClient': youtubePlayerClient,
      });
      talker.info(
        'Análisis en Android: ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s '
        '(motor: ${result?['engine'] ?? 'yt-dlp'})',
      );

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
    // Cada descarga lleva un id: el lado nativo reenvía el último estado al suscribirse,
    // y así no se confunde con el resultado de una descarga anterior.
    final id = '${DateTime.now().microsecondsSinceEpoch}-${url.hashCode.toUnsigned(32)}';
    final controller = _listenTo(
      id,
      initial: const DownloadProgress(
        status: DownloadStatus.downloading,
        percentage: 0.0,
        currentStep: 'Iniciando descarga en dispositivo móvil...',
      ),
    );

    // yt-dlp descarga en una carpeta privada de la app y el lado nativo exporta el
    // archivo al destino (MediaStore o SAF), que resuelve también los nombres repetidos.
    final title = (customTitle == null || customTitle.trim().isEmpty) ? 'video' : customTitle.trim();
    final baseName = '${DesktopProcessEngine.sanitizeFilename(title)} [${DesktopProcessEngine.getQualityTag(option)}]';

    Future<void> start() async {
      // Android 7–9 necesita permiso para escribir en Download/ (desde Android 10 se usa MediaStore).
      if (destination.androidTreeUri == null) {
        final granted = await _folderChannel.invokeMethod<bool>('ensureStoragePermission') ?? false;
        if (!granted) {
          throw PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'Se necesita permiso de almacenamiento para guardar en Descargas.',
          );
        }
      }
      // Android 13+: notificación de progreso. Si se deniega, la descarga sigue igual.
      await _channel.invokeMethod<bool>('ensureNotificationPermission');
      await _channel.invokeMethod('download', {
        'id': id,
        'url': url,
        'format': option.formatId,
        'height': option.height,
        'isAudioOnly': option.isAudioOnly,
        'audioFormat': option.extension,
        'baseName': baseName,
        'treeUri': destination.androidTreeUri,
        'subdir': destination.androidSubdir,
        'playerClient': youtubePlayerClient,
      });
    }

    start().catchError((Object err) {
      final message = err is PlatformException ? (err.message ?? err.code) : err.toString();
      if (!controller.isClosed) {
        controller.add(DownloadProgress(status: DownloadStatus.error, errorMessage: message));
        controller.close();
      }
      _activeSubscription?.cancel();
      _activeSubscription = null;
    });

    return controller.stream;
  }

  /// Si hay una descarga en curso (o un resultado que la UI no recibió, p. ej. porque la app
  /// estaba cerrada), devuelve su progreso para volver a mostrarlo. Null si no hay ninguna.
  Future<Stream<DownloadProgress>?> attachToActiveDownload() async {
    try {
      final snapshot = await _channel.invokeMapMethod<String, dynamic>('getActiveDownload');
      final id = snapshot?['id'] as String?;
      if (snapshot == null || id == null) return null;
      return _listenTo(id, initial: _toProgress(snapshot)).stream;
    } catch (e) {
      talker.warning('No se pudo recuperar la descarga en curso: $e');
      return null;
    }
  }

  StreamController<DownloadProgress> _listenTo(String id, {required DownloadProgress initial}) {
    final controller = StreamController<DownloadProgress>();

    void finish() {
      _activeSubscription?.cancel();
      _activeSubscription = null;
      if (!controller.isClosed) controller.close();
    }

    controller.add(initial);
    if (_isTerminal(initial.status)) {
      finish();
      return controller;
    }

    _activeSubscription?.cancel();
    _activeSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map || event['id'] != id || controller.isClosed) return;
        final progress = _toProgress(event);
        controller.add(progress);
        if (_isTerminal(progress.status)) finish();
      },
      onError: (err) {
        if (!controller.isClosed) {
          controller.add(DownloadProgress(status: DownloadStatus.error, errorMessage: err.toString()));
        }
        finish();
      },
    );
    return controller;
  }

  static bool _isTerminal(DownloadStatus s) =>
      s == DownloadStatus.completed || s == DownloadStatus.error || s == DownloadStatus.cancelled;

  static DownloadProgress _toProgress(Map<dynamic, dynamic> event) {
    final status = switch (event['status']?.toString()) {
      'completed' => DownloadStatus.completed,
      'error' => DownloadStatus.error,
      'cancelled' => DownloadStatus.cancelled,
      'processing' => DownloadStatus.processing,
      _ => DownloadStatus.downloading,
    };
    return DownloadProgress(
      status: status,
      percentage: ((event['progress'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 100.0),
      speed: event['speed']?.toString(),
      eta: event['eta']?.toString(),
      currentStep: event['step']?.toString() ?? 'Descargando...',
      outputFilePath: event['filePath']?.toString(),
      outputUri: event['uri']?.toString(),
      errorMessage: status == DownloadStatus.error ? event['error']?.toString() : null,
    );
  }

  /// Cancela en el servicio nativo; el evento "cancelled" llega por el EventChannel.
  @override
  void cancel() {
    _channel.invokeMethod('cancelDownload');
  }
}
