import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:talker_flutter/talker_flutter.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/download_progress.dart';
import '../../domain/models/media_info.dart';
import '../../domain/models/stream_option.dart';
import '../../domain/ports/media_engine_port.dart';
import '../../infrastructure/desktop/desktop_process_engine.dart';
import '../widgets/download_progress_card.dart';
import '../widgets/empty_state_card.dart';
import '../widgets/media_preview_card.dart';
import '../widgets/media_preview_skeleton.dart';
import '../widgets/quality_selector_card.dart';
import '../widgets/url_input_card.dart';

/// Pantalla principal adaptativa de Media Downloader.
/// Orquesta la verificación de dependencias del sistema (yt-dlp, FFmpeg),
/// atajos de teclado de escritorio, detección inteligente de portapapeles,
/// layouts responsivos (Desktop vs Mobile) y el ciclo de vida de descargas.
class HomeScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDarkMode;

  const HomeScreen({
    super.key,
    required this.onToggleTheme,
    required this.isDarkMode,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final TextEditingController _urlController = TextEditingController();
  final IMediaEngine _engine = DesktopProcessEngine();

  bool _isCheckingSystem = true;
  bool _hasYtDlp = false;
  bool _hasFFmpeg = false;

  bool _isAnalyzing = false;
  bool _isDownloading = false;

  MediaInfo? _mediaInfo;
  DownloadProgress? _downloadProgress;
  StreamSubscription<DownloadProgress>? _downloadSub;
  StreamOption? _lastSelectedOption;

  String _downloadDirectory = '';
  String? _clipboardDetectedUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSystemRequirements();
    _initDownloadDirectory();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    _downloadSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboardForMediaUrl();
    }
  }

  /// Detección inteligente de URL en portapapeles al enfocar la ventana.
  Future<void> _checkClipboardForMediaUrl() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.startsWith('http://') || text.startsWith('https://')) {
        if (text != _urlController.text.trim() && text != _clipboardDetectedUrl) {
          if (mounted) {
            setState(() {
              _clipboardDetectedUrl = text;
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _checkSystemRequirements() async {
    final ytdlp = await _engine.isYtDlpAvailable();
    final ffmpeg = await _engine.isFFmpegAvailable();

    if (mounted) {
      setState(() {
        _hasYtDlp = ytdlp;
        _hasFFmpeg = ffmpeg;
        _isCheckingSystem = false;
      });
    }
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

  Future<void> _analyzeUrl([String? explicitUrl]) async {
    if (explicitUrl != null) {
      _urlController.text = explicitUrl;
    }

    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Por favor, ingresa o pega una URL válida'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _mediaInfo = null;
      _downloadProgress = null;
      _clipboardDetectedUrl = null;
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
    if (text.isNotEmpty) {
      _analyzeUrl(text);
    }
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
              if (!_isCheckingSystem) ...[
                _StatusBadge(label: 'yt-dlp', isOk: _hasYtDlp),
                const SizedBox(width: 6),
                _StatusBadge(label: 'FFmpeg', isOk: _hasFFmpeg),
                const SizedBox(width: 8),
              ],
              IconButton(
                tooltip: 'Consola de Diagnóstico (Talker)',
                icon: const Icon(Icons.terminal_rounded),
                onPressed: _openLogs,
              ),
              IconButton(
                tooltip: widget.isDarkMode ? 'Cambiar a Modo Claro' : 'Cambiar a Modo Oscuro',
                icon: Icon(
                  widget.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                ),
                onPressed: widget.onToggleTheme,
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: LayoutBuilder(
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
                        // Notificación contextual de portapapeles detectado
                        if (_clipboardDetectedUrl != null) ...[
                          _buildClipboardBanner(context, theme),
                          const SizedBox(height: 14),
                        ],

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

                        // Estado Vacío Ilustrativo
                        if (_mediaInfo == null && !_isAnalyzing && _downloadProgress == null) ...[
                          EmptyStateCard(
                            onPasteFromClipboard: _pasteFromClipboardAction,
                          ),
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
    );
  }

  Widget _buildClipboardBanner(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.content_paste_search_rounded,
              color: theme.colorScheme.onPrimaryContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Enlace detectado en el portapapeles: $_clipboardDetectedUrl',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () => _analyzeUrl(_clipboardDetectedUrl),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Analizar'),
          ),
          IconButton(
            tooltip: 'Ignorar',
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => setState(() => _clipboardDetectedUrl = null),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryBar(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
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
            message: 'Abrir carpeta en el explorador de archivos del sistema',
            child: InkWell(
              onTap: _openDownloadsFolder,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.open_in_new_rounded, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Abrir',
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

class _StatusBadge extends StatelessWidget {
  final String label;
  final bool isOk;

  const _StatusBadge({required this.label, required this.isOk});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isOk ? theme.colorScheme.tertiary : theme.colorScheme.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
