class Formatters {
  static String formatDuration(int? totalSeconds) {
    if (totalSeconds == null || totalSeconds <= 0) return '00:00';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  static String formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return 'Desconocido';
    final (value, unit) = _scale(bytes);
    return '${value.toStringAsFixed(1)} $unit';
  }

  /// Peso corto para mostrar junto a una opción: `64 MB`, `5.2 MB`, con `~` si es estimado;
  /// null si no se conoce.
  static String? formatSize(int? bytes, {bool approx = false}) {
    if (bytes == null || bytes <= 0) return null;
    final (value, unit) = _scale(bytes);
    return '${approx ? '~' : ''}${value.toStringAsFixed(value >= 10 ? 0 : 1)} $unit';
  }

  static (double, String) _scale(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return (d, suffixes[i]);
  }
}
