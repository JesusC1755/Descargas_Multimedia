import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/models/download_progress.dart';
import '../../domain/models/media_info.dart';
import '../../domain/models/stream_option.dart';
import '../../domain/ports/media_engine_port.dart';
import '../../infrastructure/desktop/desktop_process_engine.dart';
import '../widgets/download_progress_card.dart';
import '../widgets/media_preview_card.dart';
import '../widgets/quality_selector_card.dart';
import '../widgets/url_input_card.dart';

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

class _HomeScreenState extends State<HomeScreen> {
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
  }

  Future<void> _analyzeUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, ingresa una URL válida')),
      );
      return;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text('Error al analizar: $e'),
          ),
        );
      }
    }
  }

  void _startDownload(StreamOption option) {
    if (_mediaInfo == null || _downloadDirectory.isEmpty) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = const DownloadProgress(
        status: DownloadStatus.downloading,
        percentage: 0.0,
        currentStep: 'Iniciando descarga...',
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
        errorMessage: 'Descarga cancelada por el usuario.',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.cloud_download_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            const Text(
              'Media Downloader Desktop',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          if (!_isCheckingSystem) ...[
            _StatusBadge(
              label: 'yt-dlp',
              isOk: _hasYtDlp,
            ),
            const SizedBox(width: 8),
            _StatusBadge(
              label: 'FFmpeg',
              isOk: _hasFFmpeg,
            ),
            const SizedBox(width: 16),
          ],
          IconButton(
            tooltip: widget.isDarkMode ? 'Modo Claro' : 'Modo Oscuro',
            icon: Icon(
              widget.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
            onPressed: widget.onToggleTheme,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.folder_outlined, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Carpeta de descarga: ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _downloadDirectory.isNotEmpty ? _downloadDirectory : 'Determinando...',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                UrlInputCard(
                  controller: _urlController,
                  isLoading: _isAnalyzing,
                  onAnalyze: _analyzeUrl,
                ),
                const SizedBox(height: 16),
                if (_downloadProgress != null) ...[
                  DownloadProgressCard(
                    progress: _downloadProgress!,
                    onCancel: _cancelDownload,
                  ),
                  const SizedBox(height: 16),
                ],
                if (_mediaInfo != null) ...[
                  MediaPreviewCard(mediaInfo: _mediaInfo!),
                  const SizedBox(height: 16),
                  QualitySelectorCard(
                    mediaInfo: _mediaInfo!,
                    isDownloading: _isDownloading,
                    onStartDownload: _startDownload,
                  ),
                ],
              ],
            ),
          ),
        ),
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
    final color = isOk ? Colors.green : Colors.red;
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
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
