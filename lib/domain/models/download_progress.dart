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
  final String? outputFilePath;

  const DownloadProgress({
    this.status = DownloadStatus.idle,
    this.percentage = 0.0,
    this.speed,
    this.eta,
    this.currentStep,
    this.errorMessage,
    this.outputFilePath,
  });

  DownloadProgress copyWith({
    DownloadStatus? status,
    double? percentage,
    String? speed,
    String? eta,
    String? currentStep,
    String? errorMessage,
    String? outputFilePath,
  }) {
    return DownloadProgress(
      status: status ?? this.status,
      percentage: percentage ?? this.percentage,
      speed: speed ?? this.speed,
      eta: eta ?? this.eta,
      currentStep: currentStep ?? this.currentStep,
      errorMessage: errorMessage ?? this.errorMessage,
      outputFilePath: outputFilePath ?? this.outputFilePath,
    );
  }
}
