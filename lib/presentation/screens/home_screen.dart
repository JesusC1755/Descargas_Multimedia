import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:talker_flutter/talker_flutter.dart';

import '../../core/logging/app_logger.dart';
import '../../core/utils/media_url_validator.dart';
import '../../domain/models/download_progress.dart';
import '../../domain/models/media_info.dart';
import '../../domain/models/stream_option.dart';
import '../../domain/ports/media_engine_port.dart';
import '../../infrastructure/desktop/desktop_process_engine.dart';
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
  final IMediaEngine _engine = DesktopProcessEngine();

  bool _isAnalyzing = false;
  bool _isDownloading = false;

  MediaInfo? _mediaInfo;
  DownloadProgress? _downloadProgress;
  StreamSubscription<DownloadProgress>? _downloadSub;
  StreamOption? _lastSelectedOption;

  String _downloadDirectory = '';

  @override
  void initState() {
    super.initState();
    _checkSystemRequirements();
    _initDownloadDirectory();
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

  Future<void> _initDownloadDirectory() async {
    try {
      final dir = await getDownloadsDirectory();
      if (dir != null && mounted) {
        setState(() => _downloadDirectory = dir.path);
        talker.info('Carpeta de descargas detectada: ${dir.path}');
        return;
      }
    } catch (_) {}

    final home = Platform.environment['HOME'] ?? '';
    final defaultDir = Directory('$home/Descargas');
    if (await defaultDir.exists()) {
      if (mounted) setState(() => _downloadDirectory = defaultDir.path);
    } else {
      if (mounted) setState(() => _downloadDirectory = '$home/Downloads');
    }
    talker.info('Carpeta de descargas fallback: $_downloadDirectory');
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
      }
    } catch (e) {
      talker.warning('No se pudo abrir el explorador de archivos: $e');
    }
  }

  Future<void> _selectDownloadDirectory() async {
    String? newPath;

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
          if (out.isNotEmpty && Directory(out).existsSync()) {
            newPath = out;
          }
        } else if (result.exitCode == 1) {
          // El usuario canceló la selección nativa
          return;
        }
      } else if (Platform.isMacOS) {
        final result = await Process.run('osascript', [
          '-e',
          'POSIX path of (choose folder with prompt "Seleccionar carpeta de descargas")',
        ]);
        if (result.exitCode == 0) {
          final out = result.stdout.toString().trim();
          if (out.isNotEmpty && Directory(out).existsSync()) {
            newPath = out;
          }
        } else {
          return;
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
          if (out.isNotEmpty && Directory(out).existsSync()) {
            newPath = out;
          }
        }
      }
    } catch (e) {
      talker.warning('Selector nativo no disponible o error: $e');
    }

    if (newPath != null && mounted) {
      setState(() => _downloadDirectory = newPath!);
      talker.info('Carpeta de descargas actualizada: $newPath');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Carpeta de descarga cambiada a: $newPath'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    if (!mounted) return;
    await _showCustomFolderDialog();
  }

  Future<void> _showCustomFolderDialog() async {
    final controller = TextEditingController(text: _downloadDirectory);
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

    final commonFolders = <String, String>{
      'Descargas': Directory('$home/Descargas').existsSync() ? '$home/Descargas' : '$home/Downloads',
      'Videos': Directory('$home/Videos').existsSync() ? '$home/Videos' : '$home/Vídeos',
      'Música': Directory('$home/Música').existsSync() ? '$home/Música' : '$home/Music',
      'Documentos': Directory('$home/Documentos').existsSync() ? '$home/Documentos' : '$home/Documents',
      'Escritorio': Directory('$home/Escritorio').existsSync() ? '$home/Escritorio' : '$home/Desktop',
    };

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Icon(Icons.folder_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              const Text('Elegir Carpeta de Descargas'),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Ruta de la carpeta',
                    hintText: '/home/usuario/Descargas',
                    prefixIcon: Icon(Icons.folder_open_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Ubicaciones comunes:',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: commonFolders.entries.map((entry) {
                    return ActionChip(
                      avatar: const Icon(Icons.folder_special_rounded, size: 14),
                      label: Text(entry.key),
                      onPressed: () {
                        controller.text = entry.value;
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty && Directory(text).existsSync()) {
                  setState(() => _downloadDirectory = text);
                  Navigator.of(ctx).pop();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('La carpeta especificada no existe en el sistema'),
                      backgroundColor: theme.colorScheme.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text('Guardar'),
            ),
          ],
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
            action: SnackBarAction(
              textColor: theme.colorScheme.error,
              label: 'Ver Logs',
              onPressed: _openLogs,
            ),
          ),
        );
      }
    }
  }

  void _startDownload(StreamOption option) {
    if (_mediaInfo == null || _downloadDirectory.isEmpty) return;

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
        .download(
          url: _mediaInfo!.url,
          option: option,
          downloadDir: _downloadDirectory,
        )
        .listen(
          (progress) {
            if (mounted) {
              setState(() {
                _downloadProgress = progress;
                if (progress.status == DownloadStatus.completed ||
                    progress.status == DownloadStatus.error) {
                  _isDownloading = false;
                }
              });
            }
          },
          onError: (err) {
            if (mounted) {
              setState(() {
                _isDownloading = false;
                _downloadProgress = DownloadProgress(
                  status: DownloadStatus.error,
                  errorMessage: err.toString(),
                );
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TalkerScreen(talker: talker),
      ),
    );
  }

  Future<void> _pasteFromClipboardAction() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;

    final validation = MediaUrlValidator.validate(text);
    if (!validation.isValid) {
      _urlController.text = text;
      if (mounted) {
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
                    validation.errorMessage ??
                        'El texto del portapapeles no corresponde a un video compatible.',
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return;
    }

    _analyzeUrl(validation.cleanUrl ?? text);
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
        child: Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.cloud_download_rounded,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Media Downloader',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Consola de Diagnóstico (Talker)',
                icon: const Icon(Icons.terminal_rounded),
                onPressed: _openLogs,
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: AmbientMeshBackground(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktopWide = constraints.maxWidth >= 960;

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                        UrlInputCard(
                          controller: _urlController,
                          isLoading: _isAnalyzing,
                          onAnalyze: _analyzeUrl,
                        ),
                        const SizedBox(height: 16),

                        // Monitor de Descarga Activa / Progreso
                        if (_downloadProgress != null) ...[
                          DownloadProgressCard(
                            progress: _downloadProgress!,
                            onCancel: _cancelDownload,
                            onOpenFolder: _openDownloadsFolder,
                            onRetry: _lastSelectedOption != null
                                ? () => _startDownload(_lastSelectedOption!)
                                : null,
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Estado de Carga Esquelética
                        if (_isAnalyzing) ...[
                          const MediaPreviewSkeleton(),
                          const SizedBox(height: 16),
                        ],

                        // Vista de Opciones (Responsive: 2 columnas en Desktop ancho vs 1 en compacto)
                        if (_mediaInfo != null && !_isAnalyzing) ...[
                          if (isDesktopWide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: MediaPreviewCard(mediaInfo: _mediaInfo!),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 6,
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
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_special_outlined, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Text(
            'Carpeta de destino: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Text(
              _downloadDirectory.isNotEmpty ? _downloadDirectory : 'Determinando directorio...',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Seleccionar una nueva carpeta de destino',
            child: InkWell(
              onTap: _selectDownloadDirectory,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open_rounded, size: 15, color: theme.colorScheme.primary),
                    const SizedBox(width: 5),
                    Text(
                      'Cambiar',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

