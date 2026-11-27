import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:talker_flutter/talker_flutter.dart';

import '../../core/logging/app_logger.dart';
import '../../core/utils/media_url_validator.dart';
import '../../domain/models/download_progress.dart';
import '../../domain/models/media_info.dart';
import '../../domain/models/stream_option.dart';
import '../../domain/ports/media_engine_port.dart';
import '../../infrastructure/android/android_native_engine.dart';
import '../../infrastructure/media_engine_factory.dart';
import '../controllers/download_folders_controller.dart';
import '../widgets/ambient_mesh_background.dart';
import '../widgets/download_progress_card.dart';
import '../widgets/media_preview_card.dart';
import '../widgets/media_preview_skeleton.dart';
import '../widgets/quality_selector_card.dart';
import '../widgets/settings_sheet.dart';
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

  final DownloadFoldersController _folders = DownloadFoldersController();

  @override
  void initState() {
    super.initState();
    _checkSystemRequirements();
    _loadFolders();
    _restoreActiveDownload();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _downloadSub?.cancel();
    _folders.dispose();
    super.dispose();
  }

  Future<void> _checkSystemRequirements() async {
    final ytdlp = await _engine.isYtDlpAvailable();
    final ffmpeg = await _engine.isFFmpegAvailable();

    if (!ytdlp) talker.warning('yt-dlp no fue detectado en las rutas del sistema.');
    if (!ffmpeg) talker.warning('FFmpeg no fue detectado en las rutas del sistema.');
  }

  Future<void> _loadFolders() async {
    final lost = await _folders.load();
    if (lost.isNotEmpty) {
      _showInfoSnackBar('Ya no hay acceso a "${lost.first}". Se usará la carpeta predeterminada.');
    }
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

  static StreamType _typeOf(StreamOption? option) =>
      option?.isAudioOnly == true ? StreamType.audioOnly : StreamType.video;

  /// Abre la carpeta donde se guardó la última descarga.
  Future<void> _openDownloadsFolder() async {
    if (!await _folders.open(_typeOf(_lastSelectedOption))) {
      _showInfoSnackBar('No se encontró un explorador de archivos compatible.');
    }
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

  Future<void> _startDownload(StreamOption option) async {
    final mediaInfo = _mediaInfo;
    if (mediaInfo == null || !_folders.isLoaded) return;

    _lastSelectedOption = option;

    setState(() {
      _isDownloading = true;
      _downloadProgress = const DownloadProgress(
        status: DownloadStatus.downloading,
        percentage: 0.0,
        currentStep: 'Iniciando descarga de flujo...',
      );
    });

    try {
      final destination = await _folders.prepare(_typeOf(option));
      _listenToDownload(
        _engine.download(
          url: mediaInfo.url,
          option: option,
          destination: destination,
          customTitle: mediaInfo.title,
        ),
      );
    } catch (e) {
      talker.error('No se pudo preparar la carpeta de destino', e);
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadProgress = DownloadProgress(
          status: DownloadStatus.error,
          errorMessage: 'No se pudo usar la carpeta de destino: $e',
        );
      });
    }
  }

  /// Android: si la descarga siguió en segundo plano (o terminó con la app cerrada),
  /// vuelve a mostrar su progreso al abrir la app.
  Future<void> _restoreActiveDownload() async {
    final engine = _engine;
    if (engine is! AndroidNativeEngine) return;
    final stream = await engine.attachToActiveDownload();
    if (stream == null || !mounted) return;
    talker.info('Recuperando la descarga en segundo plano');
    setState(() => _isDownloading = true);
    _listenToDownload(stream);
  }

  void _listenToDownload(Stream<DownloadProgress> stream) {
    _downloadSub?.cancel();
    _downloadSub = stream.listen(
      (progress) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
            if (progress.status == DownloadStatus.completed ||
                progress.status == DownloadStatus.error ||
                progress.status == DownloadStatus.cancelled) {
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
        status: DownloadStatus.cancelled,
        currentStep: 'Descarga cancelada',
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
            body: SafeArea(
              bottom: false,
              child: LayoutBuilder(
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
                                onRetry:
                                    _lastSelectedOption != null ? () => _startDownload(_lastSelectedOption!) : null,
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
                                      child: MediaPreviewCard(
                                        mediaInfo: _mediaInfo!,
                                      ),
                                    ),
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
                                MediaPreviewCard(
                                  mediaInfo: _mediaInfo!,
                                ),
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
      ),
    );
  }

  /// Barra de carpetas de destino (video y audio) con acceso a los ajustes. En pantallas
  /// angostas los botones pasan a ser solo iconos para que las rutas siempre queden visibles.
  Widget _buildDirectoryBar(BuildContext context, ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.0),
          ),
          child: Row(
            children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: _folders,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildFolderLine(Icons.videocam_rounded, _folders.of(StreamType.video)?.displayPath),
                      const SizedBox(height: 4),
                      _buildFolderLine(Icons.music_note_rounded, _folders.of(StreamType.audioOnly)?.displayPath),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildBarButton(
                tooltip: 'Carpetas de descarga y permisos',
                icon: Icons.settings_rounded,
                label: compact ? null : 'Ajustes',
                onTap: () => showSettingsSheet(context, folders: _folders),
              ),
              if (kDebugMode) ...[
                const SizedBox(width: 6),
                _buildBarButton(
                  tooltip: 'Abrir terminal de depuración (Talker)',
                  icon: Icons.terminal_rounded,
                  label: compact ? null : 'Logs',
                  onTap: _openLogs,
                  accent: true,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildFolderLine(IconData icon, String? path) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFFA855F7)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            path ?? 'Determinando carpeta…',
            style: const TextStyle(fontSize: 12, color: Color(0xFFE9D5FF), fontFamily: 'monospace'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildBarButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
    String? label,
    bool accent = false,
  }) {
    final accentColor = const Color(0xFFA855F7);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: label == null ? 8 : 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: accent ? accentColor.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: accent ? accentColor : const Color(0xFFD8B4FE)),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
