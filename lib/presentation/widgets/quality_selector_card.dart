import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models/media_info.dart';
import '../../domain/models/stream_option.dart';

/// Selector interactivo y ergonómico de formatos y calidades multimedia.
/// Implementa la estética glassmórfica oscura de [design.html] con:
/// - Control segmentado de modo (Video MP4 / Solo Audio).
/// - Cuadrícula compacta de 2 columnas con insignias tonales e indicadores de selección.
/// - Botón de acción con gradiente vibrante y resplandor.
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
    final isVideo = _selectedType == StreamType.video;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF14141E),
            Color(0xFF0F0F17),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Encabezado y control segmentado (Video / Audio)
            _buildHeader(context),
            const SizedBox(height: 14),

            // Línea divisoria
            Divider(
              color: Colors.white.withValues(alpha: 0.06),
              height: 1,
              thickness: 1,
            ),
            const SizedBox(height: 12),

            // Encabezado de la cuadrícula de opciones
            Row(
              children: [
                Icon(
                  isVideo ? Icons.tune_rounded : Icons.equalizer_rounded,
                  size: 15,
                  color: isVideo ? const Color(0xFFA855F7) : const Color(0xFF06B6D4),
                ),
                const SizedBox(width: 8),
                Text(
                  isVideo ? 'Resoluciones disponibles:' : 'Formatos y códecs de audio:',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE2E8F0),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Cuadrícula Compacta de 2 Columnas (40px por fila)
            if (options.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child: Center(
                  child: Text(
                    'No hay opciones disponibles para este modo.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final int crossAxisCount = constraints.maxWidth < 360 ? 1 : 2;

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
                        isAudio: !isVideo,
                        onTap: widget.isDownloading
                            ? null
                            : () => setState(() => _selectedOption = opt),
                      );
                    },
                  );
                },
              ),

            const SizedBox(height: 16),

            // Botón de acción principal de Descarga
            _buildDownloadButton(context, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 420;

        final titleWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Modalidad de Descarga',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Selecciona el formato y la calidad deseada',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        );

        final toggleWidget = _buildModeToggle();

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
    );
  }

  Widget _buildModeToggle() {
    final isVideo = _selectedType == StreamType.video;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeTab(
            label: 'Video (MP4)',
            icon: Icons.videocam_rounded,
            isSelected: isVideo,
            gradient: const LinearGradient(
              colors: [Color(0xFF9333EA), Color(0xFF4F46E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shadowColor: const Color(0xFF9333EA).withValues(alpha: 0.35),
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
            label: 'Solo Audio',
            icon: Icons.headphones_rounded,
            isSelected: !isVideo,
            gradient: const LinearGradient(
              colors: [Color(0xFF06B6D4), Color(0xFF2563EB)],
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
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
              size: 15,
              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
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
        ? const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF2563EB), Color(0xFF4F46E5)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          )
        : AppTheme.audioGradient;

    final Color shadowColor = isVideo
        ? const Color(0xFF6366F1).withValues(alpha: 0.38)
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
              : const Color(0xFF262638).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: isEnabled
              ? Border.all(
                  color: const Color(0xFF60A5FA).withValues(alpha: 0.35),
                  width: 1,
                )
              : null,
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
                  size: 19,
                  color: isEnabled
                      ? Colors.white
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 8),
                Text(
                  isVideo ? 'Descargar Video' : 'Extraer Audio',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isEnabled
                        ? Colors.white
                        : const Color(0xFF64748B),
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
    final badgeLabel = _getShortBadge();
    final cleanLabel = _getLabel();

    final Color activeAccent = isAudio
        ? const Color(0xFF06B6D4) // Electric Cyan
        : const Color(0xFFA855F7); // Neon Purple

    final Color activeContainerBg = isAudio
        ? const Color(0xFF0369A1).withValues(alpha: 0.25)
        : const Color(0xFF581C87).withValues(alpha: 0.25);

    return Tooltip(
      message: option.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? activeContainerBg : Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? activeAccent.withValues(alpha: 0.7)
                  : Colors.white.withValues(alpha: 0.08),
              width: isSelected ? 1.4 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: activeAccent.withValues(alpha: 0.25),
                      blurRadius: 10,
                      spreadRadius: -1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              // Badge de resolución / formato (FHD, 4K, MP3...)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? (isAudio
                          ? const LinearGradient(
                              colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                            )
                          : const LinearGradient(
                              colors: [Color(0xFFA855F7), Color(0xFF6366F1)],
                            ))
                      : null,
                  color: isSelected ? null : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(5),
                  border: isSelected
                      ? null
                      : Border.all(
                          color: Colors.white.withValues(alpha: 0.04),
                          width: 1,
                        ),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                    letterSpacing: 0.3,
                    color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Etiqueta de resolución o tasa de bits
              Expanded(
                child: Text(
                  cleanLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Indicador derecho: Insignia de verificación si está seleccionado, o círculo sutil si no
              if (isSelected)
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: activeAccent.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: activeAccent.withValues(alpha: 0.6),
                      width: 1.2,
                    ),
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 13,
                    color: isAudio ? const Color(0xFF67E8F9) : const Color(0xFFD8B4FE),
                  ),
                )
              else
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: activeAccent.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
