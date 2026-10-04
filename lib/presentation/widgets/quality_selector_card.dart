import 'package:flutter/material.dart';
import '../../core/utils/formatters.dart';
import '../../domain/models/media_info.dart';
import '../../domain/models/stream_option.dart';

/// Selector interactivo y ergonómico de formatos y calidades multimedia.
/// Organiza resoluciones de video (4K, 1080p, etc.) y formatos de audio (MP3, FLAC, M4A)
/// en tarjetas visuales seleccionables con badges de bitrate, tamaño y contenedor.
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
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado con selector de Modo (SegmentedButton)
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 520;
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
                      const SizedBox(height: 12),
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
            const SizedBox(height: 16),
            Divider(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              height: 1,
            ),
            const SizedBox(height: 16),

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
            const SizedBox(height: 14),

            // Cuadrícula/Lista de Opciones
            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
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
                  final crossAxisCount = constraints.maxWidth > 650
                      ? 3
                      : constraints.maxWidth > 420
                          ? 2
                          : 1;

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: crossAxisCount == 1 ? 4.2 : 2.5,
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

            const SizedBox(height: 22),

            // Botón Principal de Descarga
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: (widget.isDownloading || _selectedOption == null)
                    ? null
                    : () => widget.onStartDownload(_selectedOption!),
                icon: const Icon(Icons.downloading_rounded, size: 22),
                label: Text(
                  _selectedType == StreamType.video
                      ? 'Descargar Video en ${_selectedOption?.label ?? ""}'
                      : 'Extraer Audio en ${_selectedOption?.extension.toUpperCase() ?? ""}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
                style: FilledButton.styleFrom(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
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

  String _getQualityBadge() {
    if (isAudio) {
      return option.extension.toUpperCase();
    }
    final h = option.height ?? 0;
    if (h >= 2160) return '4K UHD';
    if (h >= 1440) return '2K QHD';
    if (h >= 1080) return 'FHD';
    if (h >= 720) return 'HD';
    return 'SD';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeLabel = _getQualityBadge();

    final isHighRes = (option.height ?? 0) >= 1080 ||
        option.extension.toLowerCase() == 'flac' ||
        (option.note?.contains('320') ?? false);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primary
                    : isHighRes
                        ? theme.colorScheme.tertiaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badgeLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? theme.colorScheme.onPrimary
                      : isHighRes
                          ? theme.colorScheme.onTertiaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    option.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (option.filesize != null || option.note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      option.filesize != null
                          ? 'Aprox. ${Formatters.formatBytes(option.filesize)}'
                          : (option.note ?? ''),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}
