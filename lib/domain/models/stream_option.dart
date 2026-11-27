enum StreamType { video, audioOnly }

class StreamOption {
  final String formatId;
  final String label; // Ej. "1080p (Full HD)", "MP3 (Alta Calidad)"
  final String extension; // "mp4", "mp3", "m4a", etc.
  final int? height;
  final int? filesize;

  /// El peso es una estimación (bitrate × duración), no el tamaño real.
  final bool filesizeIsApprox;
  final String? note;
  final bool isAudioOnly;

  const StreamOption({
    required this.formatId,
    required this.label,
    required this.extension,
    this.height,
    this.filesize,
    this.filesizeIsApprox = false,
    this.note,
    this.isAudioOnly = false,
  });

  @override
  String toString() => label;
}
