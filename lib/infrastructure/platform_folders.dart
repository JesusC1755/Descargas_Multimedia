import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/logging/app_logger.dart';
import '../domain/models/download_destination.dart';

/// Carpetas del sistema: carpeta de descargas, selector nativo y explorador de archivos.
/// En Android las carpetas se eligen con SAF y se guardan como URI con permiso persistente.
class PlatformFolders {
  static const MethodChannel _channel = MethodChannel('com.example.media_downloader/folder_picker');

  /// Carpeta de descargas del sistema. En Android, la pública `Download/` (path_provider
  /// devuelve una carpeta privada de la app, invisible para la galería).
  static Future<String> downloadsPath() async {
    if (Platform.isAndroid) {
      return await _channel.invokeMethod<String>('getDefaultDestination') ?? '/storage/emulated/0/Download';
    }
    try {
      final dir = await getDownloadsDirectory();
      if (dir != null) return dir.path;
    } catch (_) {}
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final es = Directory('$home${Platform.pathSeparator}Descargas');
    return es.existsSync() ? es.path : '$home${Platform.pathSeparator}Downloads';
  }

  /// Abre el selector de carpetas del sistema, empezando en [current]. Null si se cancela.
  static Future<DownloadDestination?> pick({DownloadDestination? current}) async {
    try {
      if (Platform.isAndroid) {
        final picked = await _channel.invokeMapMethod<String, dynamic>('pickFolder', {
          'initialUri': current?.androidTreeUri,
        });
        final uri = picked?['uri'] as String?;
        if (uri == null) return null;
        return DownloadDestination(displayPath: picked?['path'] as String? ?? uri, androidTreeUri: uri);
      }
      final path = await _pickDesktopPath(current?.displayPath);
      return path == null ? null : DownloadDestination(displayPath: path);
    } catch (e) {
      talker.warning('No se pudo seleccionar la carpeta: $e');
      return null;
    }
  }

  /// ¿Se puede seguir escribiendo en la carpeta? (Android: permiso SAF vigente.)
  static Future<bool> isAccessible(DownloadDestination d) async {
    try {
      if (Platform.isAndroid) {
        if (d.androidTreeUri == null) return true;
        return await _channel.invokeMethod<bool>('checkTreeAccess', {'uri': d.androidTreeUri}) ?? false;
      }
      return Directory(d.displayPath).existsSync();
    } catch (e) {
      talker.warning('No se pudo verificar la carpeta ${d.displayPath}: $e');
      return false;
    }
  }

  /// Abre la carpeta en el explorador de archivos. False si no hay ninguno compatible.
  static Future<bool> open(DownloadDestination d) async {
    try {
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<bool>('openFolder', {
              'treeUri': d.androidTreeUri,
              'subdir': d.androidSubdir,
            }) ??
            false;
      }
      final command = Platform.isWindows ? 'explorer.exe' : (Platform.isMacOS ? 'open' : 'xdg-open');
      await Process.run(command, [d.displayPath]);
      return true;
    } catch (e) {
      talker.warning('No se pudo abrir el explorador de archivos: $e');
      return false;
    }
  }

  /// Android limita los permisos SAF persistentes: se liberan los de carpetas que ya no se usan.
  static Future<void> releaseUnused(Iterable<DownloadDestination> inUse) async {
    if (!Platform.isAndroid) return;
    final keep = inUse.map((d) => d.androidTreeUri).whereType<String>().toList();
    try {
      await _channel.invokeMethod('releaseUnusedFolders', {'keep': keep});
    } catch (e) {
      talker.warning('No se pudieron liberar permisos de carpetas: $e');
    }
  }

  static Future<String?> _pickDesktopPath(String? initial) async {
    const title = 'Seleccionar carpeta de descargas';
    final ProcessResult result;
    if (Platform.isLinux) {
      result = await Process.run('zenity', [
        '--file-selection',
        '--directory',
        '--title=$title',
        if (initial != null && initial.isNotEmpty) '--filename=$initial/',
      ]);
    } else if (Platform.isWindows) {
      const script = '[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null; '
          '\$dlg = New-Object System.Windows.Forms.FolderBrowserDialog; '
          '\$dlg.Description = "$title"; '
          'if(\$dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){ Write-Output \$dlg.SelectedPath }';
      result = await Process.run('powershell', ['-NoProfile', '-Command', script]);
    } else if (Platform.isMacOS) {
      result = await Process.run('osascript', ['-e', 'POSIX path of (choose folder with prompt "$title")']);
    } else {
      return null;
    }
    final out = result.stdout.toString().trim();
    return result.exitCode == 0 && out.isNotEmpty && Directory(out).existsSync() ? out : null;
  }
}
