import 'dart:convert';

/// Carpeta de destino de las descargas.
///
/// - Escritorio: [displayPath] es la ruta real donde escribe el motor.
/// - Android: los archivos se descargan en una carpeta privada de la app y luego se
///   exportan. Si [androidTreeUri] es nulo se usa la carpeta pública `Download/` (MediaStore),
///   o su subcarpeta [androidSubdir]; si no, se exporta a la carpeta elegida por SAF
///   (`content://…`). [displayPath] solo sirve para mostrarla al usuario.
class DownloadDestination {
  final String displayPath;
  final String? androidTreeUri;
  final String? androidSubdir;

  const DownloadDestination({required this.displayPath, this.androidTreeUri, this.androidSubdir});

  String toJson() => jsonEncode({
        'displayPath': displayPath,
        if (androidTreeUri != null) 'androidTreeUri': androidTreeUri,
        if (androidSubdir != null) 'androidSubdir': androidSubdir,
      });

  static DownloadDestination? fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final path = map['displayPath'];
      if (path is! String || path.isEmpty) return null;
      final uri = map['androidTreeUri'];
      final subdir = map['androidSubdir'];
      return DownloadDestination(
        displayPath: path,
        androidTreeUri: uri is String ? uri : null,
        androidSubdir: subdir is String ? subdir : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DownloadDestination &&
      other.displayPath == displayPath &&
      other.androidTreeUri == androidTreeUri &&
      other.androidSubdir == androidSubdir;

  @override
  int get hashCode => Object.hash(displayPath, androidTreeUri, androidSubdir);
}
