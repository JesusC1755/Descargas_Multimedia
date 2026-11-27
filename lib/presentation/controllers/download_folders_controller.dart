import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/download_destination.dart';
import '../../domain/models/stream_option.dart';
import '../../infrastructure/platform_folders.dart';

/// Carpetas de destino, una para video y otra para audio. Por defecto
/// `Descargas/MediaDownloader/{Video,Audio}`; el usuario puede elegir otras.
class DownloadFoldersController extends ChangeNotifier {
  /// Clave de la versión 1.1, con una sola carpeta para todo.
  static const String _legacyKey = 'download_destination';

  final Map<StreamType, DownloadDestination> _current = {};
  final Map<StreamType, DownloadDestination> _defaults = {};

  bool get isLoaded => _current.length == StreamType.values.length;

  DownloadDestination? of(StreamType type) => _current[type];

  bool isDefault(StreamType type) => _current[type] == _defaults[type];

  /// Carga las carpetas guardadas. Devuelve las rutas de las que ya no se tiene acceso
  /// (en su lugar se usa la predeterminada).
  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final base = await PlatformFolders.downloadsPath();

    // Una carpeta personalizada de la v1.1 pasa a usarse para video y audio.
    final legacy = DownloadDestination.fromJson(prefs.getString(_legacyKey));
    await prefs.remove(_legacyKey);

    final lost = <String>[];
    for (final type in StreamType.values) {
      _defaults[type] = _defaultFor(type, base);
      var saved = DownloadDestination.fromJson(prefs.getString(_key(type)));
      if (saved == null && legacy != null && legacy.displayPath != base) {
        saved = legacy;
        await prefs.setString(_key(type), legacy.toJson());
      }
      if (saved != null && !await PlatformFolders.isAccessible(saved)) {
        talker.warning('Sin acceso a la carpeta guardada (${saved.displayPath}); se usará la predeterminada.');
        lost.add(saved.displayPath);
        await prefs.remove(_key(type));
        saved = null;
      }
      _current[type] = saved ?? _defaults[type]!;
    }
    notifyListeners();
    return lost;
  }

  Future<void> pick(StreamType type) async {
    final picked = await PlatformFolders.pick(current: _current[type]);
    if (picked != null) await _set(type, picked);
  }

  Future<void> reset(StreamType type) => _set(type, _defaults[type]!);

  /// Destino listo para escribir. En escritorio se crea la carpeta si aún no existe.
  Future<DownloadDestination> prepare(StreamType type) async {
    final destination = _current[type]!;
    if (!Platform.isAndroid) await Directory(destination.displayPath).create(recursive: true);
    return destination;
  }

  Future<bool> open(StreamType type) async => PlatformFolders.open(await prepare(type));

  Future<void> _set(StreamType type, DownloadDestination destination) async {
    _current[type] = destination;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (isDefault(type)) {
      await prefs.remove(_key(type));
    } else {
      await prefs.setString(_key(type), destination.toJson());
    }
    await PlatformFolders.releaseUnused(_current.values);
    talker.info('Carpeta de ${_name(type).toLowerCase()}: ${destination.displayPath}');
  }

  static DownloadDestination _defaultFor(StreamType type, String base) {
    final sep = Platform.pathSeparator;
    return DownloadDestination(
      displayPath: '$base${sep}MediaDownloader$sep${_name(type)}',
      androidSubdir: Platform.isAndroid ? 'MediaDownloader/${_name(type)}' : null,
    );
  }

  static String _name(StreamType type) => type == StreamType.video ? 'Video' : 'Audio';

  static String _key(StreamType type) => 'download_destination_${_name(type).toLowerCase()}';
}
