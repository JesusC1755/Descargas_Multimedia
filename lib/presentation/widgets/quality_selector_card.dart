import 'package:flutter/material.dart';
import '../../core/utils/formatters.dart';
import '../../domain/models/media_info.dart';
import '../../domain/models/stream_option.dart';

/// Selector interactivo, compacto y ergonómico de formatos y calidades multimedia.
/// Optimizado para minimizar la altura vertical y evitar desplazamientos excesivos (scroll).
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
    if (_selectedType == StreamType.video && widget.mediaInfo.videoOptions.isNotEmpty) {
      _selectedOption = widget.mediaInfo.videoOptions.first;
    } else if (widget.mediaInfo.audioOptions.isNotEmpty) {
      _selectedOption = widget.mediaInfo.audioOptions.first;
    } else {
      _selectedOption = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = _selectedType == StreamType.video
        ? widget.mediaInfo.videoOptions
        : widget.mediaInfo.audioOptions;

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
            // Encabezado con selector de Modo (SegmentedButton)
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

                final segmentWidget = SegmentedButton<StreamType>(
                  segments: const [
                    ButtonSegment(
                      value: StreamType.video,
                      icon: Icon(Icons.videocam_rounded, size: 18),
                      label: Text('Video (MP4)'),
                    ),
                    ButtonSegment(
                      value: StreamType.audioOnly,
                      icon: Icon(Icons.headphones_rounded, size: 18),
                      label: Text('Solo Audio'),
                    ),
                  ],
                  selected: {_selectedType},
                  onSelectionChanged: widget.isDownloading
                      ? null
                      : (newSet) {
                          setState(() {
                            _selectedType = newSet.first;
                            _resetSelection();
                          });
                        },
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      titleWidget,
                      const SizedBox(height: 10),
                      segmentWidget,
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    titleWidget,
                    segmentWidget,
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

            // Título de la sección de opciones
            Row(
              children: [
                Icon(
                  _selectedType == StreamType.video
                      ? Icons.tune_rounded
                      : Icons.equalizer_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
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
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 210,
                  mainAxisExtent: 40,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
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
              ),

            const SizedBox(height: 16),

            // Botón Principal de Descarga
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: (widget.isDownloading || _selectedOption == null)
                    ? null
                    : () => widget.onStartDownload(_selectedOption!),
                icon: const Icon(Icons.download_rounded, size: 20),
                label: Text(
                  _selectedType == StreamType.video
                      ? 'Descargar Video'
                      : 'Extraer Audio',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
                style: FilledButton.styleFrom(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
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

    final isHighRes = (option.height ?? 0) >= 1080 ||
        option.extension.toLowerCase() == 'flac';

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
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
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
                      ? theme.colorScheme.primary
                      : isHighRes
                          ? theme.colorScheme.tertiaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: isAudio
                    ? Icon(
                        Icons.audiotrack_rounded,
                        size: 13,
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : isHighRes
                                ? theme.colorScheme.onTertiaryContainer
                                : theme.colorScheme.onSurfaceVariant,
                      )
                    : Text(
                        badgeLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: isSelected
                              ? theme.colorScheme.onPrimary
                              : isHighRes
                                  ? theme.colorScheme.onTertiaryContainer
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
                        ? theme.colorScheme.onPrimaryContainer
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
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
