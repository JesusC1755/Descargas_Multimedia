import '../models/download_progress.dart';
import '../models/media_info.dart';
import '../models/stream_option.dart';

abstract class IMediaEngine {
  Future<bool> isYtDlpAvailable();
  Future<bool> isFFmpegAvailable();

  /// Analiza la URL y retorna la información de formatos sin descargar
  Future<MediaInfo> analyzeUrl(String url);

  /// Ejecuta la descarga y emite eventos reactivos de progreso
  Stream<DownloadProgress> download({
    required String url,
    required StreamOption option,
    required String downloadDir,
    String? customTitle,
  });

  /// Cancela la descarga en curso
  void cancel();
}
