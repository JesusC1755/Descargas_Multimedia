import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_flutter/talker_flutter.dart';

import '../../core/logging/app_logger.dart';
import '../../core/utils/media_url_validator.dart';
import '../../domain/models/download_destination.dart';
import '../../domain/models/download_progress.dart';
import '../../domain/models/media_info.dart';
import '../../domain/models/stream_option.dart';
import '../../domain/ports/media_engine_port.dart';
import '../../infrastructure/media_engine_factory.dart';
import '../widgets/ambient_mesh_background.dart';
import '../widgets/download_progress_card.dart';
import '../widgets/media_preview_card.dart';
import '../widgets/media_preview_skeleton.dart';
import '../widgets/quality_selector_card.dart';
import '../widgets/url_input_card.dart';

/// Pantalla principal adaptativa de Media Downloader.
/// Orquesta la verificación de dependencias del sistema (yt-dlp, FFmpeg),
/// atajos de teclado de escritorio, layouts responsivos (Desktop vs Mobile)
/// y el ciclo de vida de descargas.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  final IMediaEngine _engine = MediaEngineFactory.create();

  bool _isAnalyzing = false;
  bool _isDownloading = false;

  MediaInfo? _mediaInfo;
  DownloadProgress? _downloadProgress;
  StreamSubscription<DownloadProgress>? _downloadSub;
  StreamOption? _lastSelectedOption;

  static const String _destinationPrefsKey = 'download_destination';

  DownloadDestination? _destination;

  /// Ruta visible de la carpeta de destino (vacía mientras se determina).
  String get _downloadDirectory => _destination?.displayPath ?? '';

  @override
  void initState() {
    super.initState();
    _checkSystemRequirements();
    _initDestination();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _downloadSub?.cancel();
    super.dispose();
  }

  Future<void> _checkSystemRequirements() async {
    final ytdlp = await _engine.isYtDlpAvailable();
    final ffmpeg = await _engine.isFFmpegAvailable();

    if (!ytdlp) talker.warning('yt-dlp no fue detectado en las rutas del sistema.');
    if (!ffmpeg) talker.warning('FFmpeg no fue detectado en las rutas del sistema.');
  }

  /// Carga la carpeta guardada; si ya no es accesible vuelve a la predeterminada.
  Future<void> _initDestination() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = DownloadDestination.fromJson(prefs.getString(_destinationPrefsKey));

    if (saved != null) {
      if (await _isDestinationAccessible(saved)) {
        if (mounted) setState(() => _destination = saved);
        talker.info('Carpeta de destino restaurada: ${saved.displayPath}');
        return;
      }
      talker.warning('Sin acceso a la carpeta guardada (${saved.displayPath}); se usará la predeterminada.');
      await prefs.remove(_destinationPrefsKey);
      _showInfoSnackBar('Ya no hay acceso a "${saved.displayPath}". Se usará la carpeta Descargas.');
    }

    final fallback = await _defaultDestination();
    if (mounted) setState(() => _destination = fallback);
    talker.info('Carpeta de destino predeterminada: ${fallback.displayPath}');
  }

  Future<bool> _isDestinationAccessible(DownloadDestination d) async {
    try {
      if (Platform.isAndroid) {
        if (d.androidTreeUri == null) return true;
        return await _folderChannel.invokeMethod<bool>('checkTreeAccess', {'uri': d.androidTreeUri}) ?? false;
      }
      return Directory(d.displayPath).existsSync();
    } catch (e) {
      talker.warning('No se pudo verificar la carpeta de destino: $e');
      return false;
    }
  }

  Future<DownloadDestination> _defaultDestination() async {
    if (Platform.isAndroid) {
      // path_provider devuelve en Android una carpeta privada de la app (Android/data/…),
      // invisible para la galería; la predeterminada real es Download/ vía MediaStore.
      final path = await _folderChannel.invokeMethod<String>('getDefaultDestination');
      return DownloadDestination(displayPath: path ?? '/storage/emulated/0/Download');
    }

    try {
      final dir = await getDownloadsDirectory();
      if (dir != null) return DownloadDestination(displayPath: dir.path);
    } catch (_) {}

    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final es = Directory('$home${Platform.pathSeparator}Descargas');
    return DownloadDestination(displayPath: es.existsSync() ? es.path : '$home${Platform.pathSeparator}Downloads');
  }

  Future<void> _setDestination(DownloadDestination destination) async {
    setState(() => _destination = destination);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_destinationPrefsKey, destination.toJson());
    talker.info('Carpeta de destino guardada: ${destination.displayPath}');
  }

  void _showInfoSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _openDownloadsFolder() async {
    if (_downloadDirectory.isEmpty) return;
    try {
      if (Platform.isLinux) {
        await Process.run('xdg-open', [_downloadDirectory]);
      } else if (Platform.isWindows) {
        await Process.run('explorer.exe', [_downloadDirectory]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [_downloadDirectory]);
      } else if (Platform.isAndroid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Guardado en: $_downloadDirectory'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      talker.warning('No se pudo abrir el explorador de archivos: $e');
    }
  }

  static const MethodChannel _folderChannel = MethodChannel('com.example.media_downloader/folder_picker');

  Future<DownloadDestination?> _openNativeFolderPicker() async {
    final path = await _pickDesktopFolderPath();
    return path == null ? null : DownloadDestination(displayPath: path);
  }

  /// Android: carpeta elegida con SAF. Se guarda el URI (con permiso persistente) para
  /// escribir con DocumentsContract; la ruta solo se muestra.
  Future<DownloadDestination?> _pickAndroidFolder() async {
    try {
      final picked = await _folderChannel.invokeMapMethod<String, dynamic>('pickFolder');
      final uri = picked?['uri'] as String?;
      if (uri == null) return null;
      return DownloadDestination(displayPath: picked?['path'] as String? ?? uri, androidTreeUri: uri);
    } on PlatformException catch (e) {
      talker.warning('Error en selector de carpetas de Android: ${e.message}');
      _showInfoSnackBar(e.message ?? 'No se pudo seleccionar la carpeta.');
      return null;
    }
  }

  Future<String?> _pickDesktopFolderPath() async {
    try {
      if (Platform.isLinux) {
        final result = await Process.run('zenity', [
          '--file-selection',
          '--directory',
          '--title=Seleccionar carpeta de descargas',
          if (_downloadDirectory.isNotEmpty) '--filename=$_downloadDirectory/',
        ]);
        if (result.exitCode == 0) {
          final out = result.stdout.toString().trim();
          if (out.isNotEmpty && Directory(out).existsSync()) return out;
        }
      } else if (Platform.isWindows) {
        final script =
            '[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null; '
            '\$dlg = New-Object System.Windows.Forms.FolderBrowserDialog; '
            '\$dlg.Description = "Seleccionar carpeta de descargas"; '
            'if(\$dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){ Write-Output \$dlg.SelectedPath }';
        final result = await Process.run('powershell', ['-NoProfile', '-Command', script]);
        if (result.exitCode == 0) {
          final out = result.stdout.toString().trim();
          if (out.isNotEmpty && Directory(out).existsSync()) return out;
        }
      } else if (Platform.isMacOS) {
        final result = await Process.run('osascript', [
          '-e',
          'POSIX path of (choose folder with prompt "Seleccionar carpeta de descargas")',
        ]);
        if (result.exitCode == 0) {
          final out = result.stdout.toString().trim();
          if (out.isNotEmpty && Directory(out).existsSync()) return out;
        }
      }
    } catch (e) {
      talker.warning('Error en selector nativo: $e');
    }
    return null;
  }

  Future<void> _selectDownloadDirectory() async {
    final initial = _destination;
    if (initial == null) return;
    DownloadDestination currentSelected = initial;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E24),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            final selectedPath = currentSelected.displayPath;
            final folderName = selectedPath.isNotEmpty
                ? selectedPath.split(Platform.pathSeparator).where((p) => p.isNotEmpty).lastOrNull ?? selectedPath
                : 'Descargas';
            final storageLabel = selectedPath.contains('/storage/emulated/0')
                ? 'Almacenamiento interno'
                : (selectedPath.contains('/storage/') ? 'Tarjeta de memoria' : 'Almacenamiento local');

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 18),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      'Selección de carpetas',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 18),

                    // Tarjeta de la carpeta seleccionada
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.folder_rounded, color: theme.colorScheme.primary, size: 28),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  folderName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  storageLabel,
                                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  selectedPath,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: Colors.white.withValues(alpha: 0.4),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_rounded, size: 14, color: theme.colorScheme.primary),
                                const SizedBox(width: 4),
                                Text(
                                  'Activado',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    // Botón para abrir el explorador de archivos nativo del celular
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                      label: const Text(
                        'Agregar carpeta o almacenamiento',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () async {
                        final picked = Platform.isAndroid
                            ? await _pickAndroidFolder()
                            : await _openNativeFolderPicker();
                        if (picked != null) {
                          setSheetState(() => currentSelected = picked);
                          // En Android el permiso de la carpeta anterior ya se liberó: aplicar de inmediato.
                          if (mounted) await _setDestination(picked);
                        }
                      },
                    ),
                    if (Platform.isAndroid && !currentSelected.isAndroidDefault) ...[
                      const SizedBox(height: 4),
                      TextButton.icon(
                        icon: const Icon(Icons.restore_rounded, size: 18),
                        label: const Text('Usar la carpeta predeterminada (Descargas)'),
                        onPressed: () async {
                          final fallback = await _defaultDestination();
                          setSheetState(() => currentSelected = fallback);
                          if (mounted) await _setDestination(fallback);
                        },
                      ),
                    ],
                    const SizedBox(height: 12),

                    // Botón Guardar
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        _setDestination(currentSelected);
                        Navigator.of(ctx).pop();
                        _showInfoSnackBar('Carpeta de destino: ${currentSelected.displayPath}');
                      },
                      child: const Text('Guardar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _analyzeUrl([String? explicitUrl]) async {
    if (explicitUrl != null) {
      _urlController.text = explicitUrl;
    }

    final rawUrl = _urlController.text.trim();
    final validation = MediaUrlValidator.validate(rawUrl);

    if (!validation.isValid) {
      final theme = Theme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: theme.colorScheme.errorContainer,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  validation.errorMessage ?? 'Por favor, ingresa o pega un enlace de video válido.',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    final url = validation.cleanUrl ?? rawUrl;
    if (_urlController.text != url) {
      _urlController.text = url;
    }

    setState(() {
      _isAnalyzing = true;
      _mediaInfo = null;
      _downloadProgress = null;
    });

    try {
      final info = await _engine.analyzeUrl(url);
      if (mounted) {
        setState(() {
          _mediaInfo = info;
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAnalyzing = false);
        final theme = Theme.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: theme.colorScheme.errorContainer,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Error al analizar el enlace: $e',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            action: SnackBarAction(textColor: theme.colorScheme.error, label: 'Ver Logs', onPressed: _openLogs),
          ),
        );
      }
    }
  }

  void _startDownload(StreamOption option) {
    final destination = _destination;
    if (_mediaInfo == null || destination == null) return;

    _lastSelectedOption = option;

    setState(() {
      _isDownloading = true;
      _downloadProgress = const DownloadProgress(
        status: DownloadStatus.downloading,
        percentage: 0.0,
        currentStep: 'Iniciando descarga de flujo...',
      );
    });

    _downloadSub?.cancel();
    _downloadSub = _engine
        .download(url: _mediaInfo!.url, option: option, destination: destination, customTitle: _mediaInfo!.title)
        .listen(
          (progress) {
            if (mounted) {
              setState(() {
                _downloadProgress = progress;
                if (progress.status == DownloadStatus.completed || progress.status == DownloadStatus.error) {
                  _isDownloading = false;
                }
              });
            }
          },
          onError: (err) {
            if (mounted) {
              setState(() {
                _isDownloading = false;
                _downloadProgress = DownloadProgress(status: DownloadStatus.error, errorMessage: err.toString());
              });
            }
          },
        );
  }

  void _cancelDownload() {
    _engine.cancel();
    _downloadSub?.cancel();
    setState(() {
      _isDownloading = false;
      _downloadProgress = const DownloadProgress(
        status: DownloadStatus.error,
        errorMessage: 'Descarga cancelada manualmente por el usuario.',
      );
    });
  }

  void _openLogs() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TalkerScreen(talker: talker)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Atajos de teclado ergonómicos para Desktop
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_isDownloading) {
            _cancelDownload();
          } else if (_mediaInfo != null) {
            setState(() {
              _mediaInfo = null;
              _downloadProgress = null;
            });
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: AmbientMeshBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktopWide = constraints.maxWidth >= 960;

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1040),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Barra de información de ruta y acceso rápido al explorador
                          _buildDirectoryBar(context, theme),
                          const SizedBox(height: 16),

                          // Formulario de entrada de URL
                          UrlInputCard(controller: _urlController, isLoading: _isAnalyzing, onAnalyze: _analyzeUrl),
                          const SizedBox(height: 16),

                          // Monitor de Descarga Activa / Progreso
                          if (_downloadProgress != null) ...[
                            DownloadProgressCard(
                              progress: _downloadProgress!,
                              onCancel: _cancelDownload,
                              onOpenFolder: _openDownloadsFolder,
                              onRetry: _lastSelectedOption != null ? () => _startDownload(_lastSelectedOption!) : null,
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Estado de Carga Esquelética
                          if (_isAnalyzing) ...[const MediaPreviewSkeleton(), const SizedBox(height: 16)],

                          // Vista de Opciones (Responsive: 2 columnas en Desktop ancho vs 1 en compacto)
                          if (_mediaInfo != null && !_isAnalyzing) ...[
                            if (isDesktopWide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 5, child: MediaPreviewCard(mediaInfo: _mediaInfo!)),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    flex: 7,
                                    child: QualitySelectorCard(
                                      mediaInfo: _mediaInfo!,
                                      isDownloading: _isDownloading,
                                      onStartDownload: _startDownload,
                                    ),
                                  ),
                                ],
                              )
                            else ...[
                              MediaPreviewCard(mediaInfo: _mediaInfo!),
                              const SizedBox(height: 16),
                              QualitySelectorCard(
                                mediaInfo: _mediaInfo!,
                                isDownloading: _isDownloading,
                                onStartDownload: _startDownload,
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDirectoryBar(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.0),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, size: 18, color: Color(0xFFA855F7)),
          const SizedBox(width: 10),
          const Text(
            'Carpeta de destino: ',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
          ),
          Expanded(
            child: Text(
              _downloadDirectory.isNotEmpty ? _downloadDirectory : 'Determinando directorio...',
              style: const TextStyle(fontSize: 12, color: Color(0xFFE9D5FF), fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Seleccionar una nueva carpeta de destino',
            child: InkWell(
              onTap: _selectDownloadDirectory,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.0),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open_rounded, size: 14, color: Color(0xFFD8B4FE)),
                    SizedBox(width: 6),
                    Text(
                      'Cambiar',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (kDebugMode) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Abrir terminal de depuración (Talker)',
              child: InkWell(
                onTap: _openLogs,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFA855F7).withValues(alpha: 0.3), width: 1.0),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.terminal_rounded, size: 14, color: Color(0xFFA855F7)),
                      SizedBox(width: 6),
                      Text(
                        'Logs',
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: Color(0xFFE9D5FF),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
