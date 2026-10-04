import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../domain/models/media_info.dart';
import '../../domain/models/stream_option.dart';

/// Selector interactivo, compacto y ergonómico de formatos y calidades multimedia.
/// Estilo Cyberpunk / Synthwave de alto impacto visual con gradientes vivos
/// y retroalimentación táctil de precisión para escritorio y móvil.
class QualitySelectorCard extends StatefulWidget {
  final MediaInfo mediaInfo;
  final bool isDownloading;
  final Function(StreamOption selectedOption) onStartDownload;

  const QualitySelectorCard({
    super.key,
    required this.mediaInfo,
    required this.isDownloading,
    required this.onStartDownload,
  });

  @override
  State<QualitySelectorCard> createState() => _QualitySelectorCardState();
}

class _QualitySelectorCardState extends State<QualitySelectorCard> {
  StreamType _selectedType = StreamType.video;
  StreamOption? _selectedOption;

  @override
  void initState() {
    super.initState();
    _resetSelection();
  }

  @override
  void didUpdateWidget(covariant QualitySelectorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaInfo != widget.mediaInfo) {
      _resetSelection();
    }
  }

  void _resetSelection() {
    final available = _currentOptions;
    if (available.isNotEmpty) {
      if (_selectedType == StreamType.video) {
        _selectedOption = available.firstWhere(
          (opt) => (opt.height ?? 0) <= 1080,
          orElse: () => available.first,
        );
      } else {
        _selectedOption = available.firstWhere(
          (opt) => opt.extension.toLowerCase() == 'mp3',
          orElse: () => available.first,
        );
      }
    } else {
      _selectedOption = null;
    }
  }

  List<StreamOption> get _currentOptions {
    if (_selectedType == StreamType.video) {
      return widget.mediaInfo.videoOptions;
    } else {
      return widget.mediaInfo.audioOptions;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = _currentOptions;

    return Card(
      elevation: 1,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado con selector de Modo (Cápsula Cyberpunk)
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 480;
                final titleWidget = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Modalidad de Descarga',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Selecciona el formato y la calidad deseada',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );

                final toggleWidget = _buildModeToggle(context, theme);

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      titleWidget,
                      const SizedBox(height: 10),
                      toggleWidget,
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    titleWidget,
                    toggleWidget,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Divider(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              height: 1,
            ),
            const SizedBox(height: 12),

            // Título de la sección de calidades
            Row(
              children: [
                Icon(
                  _selectedType == StreamType.video
                      ? Icons.tune_rounded
                      : Icons.equalizer_rounded,
                  size: 16,
                  color: _selectedType == StreamType.video
                      ? const Color(0xFFA855F7)
                      : const Color(0xFF06B6D4),
                ),
                const SizedBox(width: 8),
                Text(
                  _selectedType == StreamType.video
                      ? 'Resoluciones disponibles:'
                      : 'Formatos y códecs de audio:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Cuadrícula Compacta de Opciones (máx 40px por fila)
            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: Text(
                    'No hay opciones disponibles para este modo.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final int crossAxisCount = constraints.maxWidth < 420
                      ? 2
                      : constraints.maxWidth < 620
                          ? 3
                          : 4;

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      mainAxisExtent: 40,
                    ),
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final opt = options[index];
                      final isSelected = _selectedOption == opt;

                      return _OptionTile(
                        option: opt,
                        isSelected: isSelected,
                        isAudio: _selectedType == StreamType.audioOnly,
                        onTap: widget.isDownloading
                            ? null
                            : () => setState(() => _selectedOption = opt),
                      );
                    },
                  );
                },
              ),

            const SizedBox(height: 16),

            // Botón Principal de Descarga con Gradiente Cyberpunk Neón
            _buildDownloadButton(context, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildModeToggle(BuildContext context, ThemeData theme) {
    final isVideo = _selectedType == StreamType.video;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.35),
          width: 1.1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeTab(
            context: context,
            theme: theme,
            label: 'Video (MP4)',
            icon: Icons.videocam_rounded,
            isSelected: isVideo,
            gradient: const LinearGradient(
              colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shadowColor: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
            onTap: () {
              if (widget.isDownloading || isVideo) return;
              setState(() {
                _selectedType = StreamType.video;
                _resetSelection();
              });
            },
          ),
          const SizedBox(width: 4),
          _buildModeTab(
            context: context,
            theme: theme,
            label: 'Solo Audio',
            icon: Icons.headphones_rounded,
            isSelected: !isVideo,
            gradient: const LinearGradient(
              colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shadowColor: const Color(0xFF06B6D4).withValues(alpha: 0.35),
            onTap: () {
              if (widget.isDownloading || !isVideo) return;
              setState(() {
                _selectedType = StreamType.audioOnly;
                _resetSelection();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab({
    required BuildContext context,
    required ThemeData theme,
    required String label,
    required IconData icon,
    required bool isSelected,
    required Gradient gradient,
    required Color shadowColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: widget.isDownloading ? null : onTap,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          gradient: isSelected ? gradient : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadButton(BuildContext context, ThemeData theme) {
    final bool isEnabled = !widget.isDownloading && _selectedOption != null;
    final bool isVideo = _selectedType == StreamType.video;

    final Gradient activeGradient = isVideo
        ? AppTheme.primaryGradient
        : AppTheme.audioGradient;

    final Color shadowColor = isVideo
        ? const Color(0xFF8B5CF6).withValues(alpha: 0.38)
        : const Color(0xFF06B6D4).withValues(alpha: 0.38);

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: isEnabled ? activeGradient : null,
          color: isEnabled
              ? null
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: isEnabled ? () => widget.onStartDownload(_selectedOption!) : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isVideo ? Icons.download_rounded : Icons.audiotrack_rounded,
                  size: 20,
                  color: isEnabled
                      ? Colors.white
                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 8),
                Text(
                  isVideo ? 'Descargar Video' : 'Extraer Audio',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isEnabled
                        ? Colors.white
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final StreamOption option;
  final bool isSelected;
  final bool isAudio;
  final VoidCallback? onTap;

  const _OptionTile({
    required this.option,
    required this.isSelected,
    required this.isAudio,
    required this.onTap,
  });

  String _getShortBadge() {
    if (isAudio) {
      return option.extension.toUpperCase();
    }
    final h = option.height ?? 0;
    if (h >= 2160) return '4K';
    if (h >= 1440) return '2K';
    if (h >= 1080) return 'FHD';
    if (h >= 720) return 'HD';
    return 'SD';
  }

  String _getLabel() {
    if (isAudio) {
      return option.extension.toUpperCase();
    }
    final h = option.height;
    if (h != null && h > 0) {
      return '${h}p';
    }
    return option.label;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeLabel = _getShortBadge();
    final cleanLabel = _getLabel();

    final Color activeAccent = isAudio
        ? const Color(0xFF38BDF8) // Electric Cyan
        : const Color(0xFFA855F7); // Neon Purple

    final Color activeContainerBg = activeAccent.withValues(alpha: 0.16);

    return Tooltip(
      message: option.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? activeContainerBg
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? activeAccent
                  : theme.colorScheme.outline.withValues(alpha: 0.3),
              width: isSelected ? 1.8 : 1.1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isAudio ? 5 : 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeAccent
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: isAudio
                    ? Icon(
                        Icons.audiotrack_rounded,
                        size: 13,
                        color: isSelected
                            ? Colors.white
                            : theme.colorScheme.onSurfaceVariant,
                      )
                    : Text(
                        badgeLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: isSelected
                              ? Colors.white
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cleanLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected
                        ? Colors.white
                        : theme.colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: activeAccent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
