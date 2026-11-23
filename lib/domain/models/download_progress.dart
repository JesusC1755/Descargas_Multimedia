enum DownloadStatus {
  idle,
  analyzing,
  downloading,
  processing,
  completed,
  error,
}

class DownloadProgress {
  final DownloadStatus status;
  final double percentage;
  final String? speed;
  final String? eta;
  final String? currentStep;
  final String? errorMessage;
  /// Ruta del archivo final para mostrar al usuario.
  final String? outputFilePath;

  /// URI `content://` del archivo final (solo Android: MediaStore o SAF).
  final String? outputUri;

  const DownloadProgress({
    this.status = DownloadStatus.idle,
    this.percentage = 0.0,
    this.speed,
    this.eta,
    this.currentStep,
    this.errorMessage,
    this.outputFilePath,
    this.outputUri,
  });

  DownloadProgress copyWith({
    DownloadStatus? status,
    double? percentage,
    String? speed,
    String? eta,
    String? currentStep,
    String? errorMessage,
    String? outputFilePath,
    String? outputUri,
  }) {
    return DownloadProgress(
      status: status ?? this.status,
      percentage: percentage ?? this.percentage,
      speed: speed ?? this.speed,
      eta: eta ?? this.eta,
      currentStep: currentStep ?? this.currentStep,
      errorMessage: errorMessage ?? this.errorMessage,
      outputFilePath: outputFilePath ?? this.outputFilePath,
      outputUri: outputUri ?? this.outputUri,
    );
  }
}
