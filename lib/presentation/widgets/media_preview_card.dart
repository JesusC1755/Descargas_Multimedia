import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../domain/models/media_info.dart';

/// Tarjeta de vista previa multimedia alineada con las especificaciones de diseño.
/// Muestra miniatura en proporción 16:9 con duración superpuesta, metadatos dinámicos
/// del video y del autor (con insignia verificada), y las insignias tonales inferiores
/// para calidades de video (Cian) y pistas de audio (Rosa/Magenta).
class MediaPreviewCard extends StatelessWidget {
  final MediaInfo mediaInfo;

  const MediaPreviewCard({
    super.key,
    required this.mediaInfo,
  });

  @override
  Widget build(BuildContext context) {
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
            // Miniatura 16:9 con superposición de gradiente y chip de duración
            _buildThumbnail(context),
            const SizedBox(height: 14),

            // Título del video con metadatos dinámicos
            SelectableText(
              mediaInfo.title,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.2,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),

            // Canal / Autor con avatar e insignia verificada
            _buildAuthorRow(),
            const SizedBox(height: 14),

            // Línea divisoria sutil
            Divider(
              color: Colors.white.withValues(alpha: 0.06),
              height: 1,
              thickness: 1,
            ),
            const SizedBox(height: 12),

            // Insignias inferiores (Calidades de video en Cian y Pistas de audio en Rosa)
            _buildBottomBadges(),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            // Imagen de la miniatura o placeholder si no está disponible
            Positioned.fill(
              child: mediaInfo.thumbnailUrl != null
                  ? Image.network(
                      mediaInfo.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: const Color(0xFF1E1E2D),
                        child: Center(
                          child: Icon(
                            Icons.broken_image_rounded,
                            size: 40,
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                      ),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: const Color(0xFF1E1E2D),
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: const Color(0xFFA855F7),
                              value: progress.expectedTotalBytes != null
                                  ? progress.cumulativeBytesLoaded /
                                      progress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                    )
                  : Container(
                      color: const Color(0xFF1E1E2D),
                      child: Center(
                        child: Icon(
                          Icons.video_library_rounded,
                          size: 40,
                          color: const Color(0xFFA855F7).withValues(alpha: 0.6),
                        ),
                      ),
                    ),
            ),

            // Gradiente oscuro inferior para mejorar el contraste de la duración
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.2),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),

            // Chip de Duración en la esquina inferior derecha
            if (mediaInfo.durationSeconds != null)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 11,
                        color: Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        Formatters.formatDuration(mediaInfo.durationSeconds),
                        style: const TextStyle(
                          color: Color(0xFFE2E8F0),
                          fontSize: 11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthorRow() {
    final authorName = mediaInfo.uploader?.isNotEmpty == true
        ? mediaInfo.uploader!
        : 'Autor desconocido';

    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFF581C87).withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFFA855F7).withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: const Icon(
            Icons.person_rounded,
            size: 13,
            color: Color(0xFFD8B4FE),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            authorName,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        const Icon(
          Icons.check_circle_rounded,
          size: 14,
          color: Color(0xFFA855F7),
        ),
      ],
    );
  }

  Widget _buildBottomBadges() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Insignia de calidades de video (Cian Eléctrico)
        _buildPill(
          icon: Icons.tv_rounded,
          label: '${mediaInfo.videoOptions.length} calidades de video',
          textColor: const Color(0xFF67E8F9),
          iconColor: const Color(0xFF22D3EE),
          bgColor: const Color(0xFF083344).withValues(alpha: 0.4),
          borderColor: const Color(0xFF06B6D4).withValues(alpha: 0.25),
        ),

        // Insignia de pistas de audio (Rosa / Magenta Neón - Señalado con flecha)
        _buildPill(
          icon: Icons.music_note_rounded,
          label: '${mediaInfo.audioOptions.length} pistas de audio',
          textColor: const Color(0xFFF472B6),
          iconColor: const Color(0xFFF472B6),
          bgColor: const Color(0xFF500724).withValues(alpha: 0.4),
          borderColor: const Color(0xFFEC4899).withValues(alpha: 0.25),
        ),
      ],
    );
  }

  Widget _buildPill({
    required IconData icon,
    required String label,
    required Color textColor,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: iconColor,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
