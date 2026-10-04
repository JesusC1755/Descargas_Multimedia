import 'package:flutter/material.dart';
import '../../domain/models/media_info.dart';
import '../../domain/models/stream_option.dart';

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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Elige el tipo de descarga',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SegmentedButton<StreamType>(
                  segments: const [
                    ButtonSegment(
                      value: StreamType.video,
                      icon: Icon(Icons.movie_creation_outlined),
                      label: Text('Video (MP4)'),
                    ),
                    ButtonSegment(
                      value: StreamType.audioOnly,
                      icon: Icon(Icons.music_note_rounded),
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
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              _selectedType == StreamType.video
                  ? 'Resolución de video disponible:'
                  : 'Formato de audio para extraer:',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((opt) {
                final isSelected = _selectedOption == opt;
                return ChoiceChip(
                  label: Text(opt.label),
                  selected: isSelected,
                  avatar: Icon(
                    _selectedType == StreamType.video
                        ? Icons.hd_rounded
                        : Icons.audiotrack_rounded,
                    size: 16,
                  ),
                  onSelected: widget.isDownloading
                      ? null
                      : (selected) {
                          if (selected) {
                            setState(() => _selectedOption = opt);
                          }
                        },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: (widget.isDownloading || _selectedOption == null)
                    ? null
                    : () => widget.onStartDownload(_selectedOption!),
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  _selectedType == StreamType.video
                      ? 'Descargar Video (${_selectedOption?.label ?? ""})'
                      : 'Extraer Audio (${_selectedOption?.extension.toUpperCase() ?? ""})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
