import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:talker_flutter/talker_flutter.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/download_progress.dart';

/// Monitor interactivo de descargas y procesamiento multimedia con estética Cyberpunk.
/// Incluye escáner de pistas segmentado por radar (Opción 3),
/// animación continua en fase indeterminada (0.0% / enlace búfer),
/// diferenciación de fases (descarga vs multiplexado FFmpeg),
/// feedback de éxito y diagnóstico de errores integrado con Talker.
class DownloadProgressCard extends StatefulWidget {
  final DownloadProgress progress;
  final VoidCallback onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenFolder;

  const DownloadProgressCard({
    super.key,
    required this.progress,
    required this.onCancel,
    this.onRetry,
    this.onOpenFolder,
  });

  @override
  State<DownloadProgressCard> createState() => _DownloadProgressCardState();
}

class _DownloadProgressCardState extends State<DownloadProgressCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _copyErrorToClipboard(BuildContext context, String message) {
    Clipboard.setData(ClipboardData(text: message));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.copy_rounded, size: 18),
            SizedBox(width: 8),
            Text('Registro de error copiado al portapapeles'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _openTalkerScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TalkerScreen(talker: talker),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDone = widget.progress.status == DownloadStatus.completed;
    final isError = widget.progress.status == DownloadStatus.error;
    final isProcessing = widget.progress.status == DownloadStatus.processing ||
        (widget.progress.currentStep?.toLowerCase().contains('ffmpeg') ?? false) ||
        (widget.progress.currentStep?.toLowerCase().contains('uniendo') ?? false);

    final borderColor = isDone
        ? theme.colorScheme.tertiary
        : isError
            ? theme.colorScheme.error
            : theme.colorScheme.primary.withValues(alpha: 0.85);

    return Card(
      elevation: 2,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: borderColor, width: 1.6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera de estado
            Row(
              children: [
                _buildStatusIcon(context, theme, isDone, isError, isProcessing),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isDone
                            ? '¡Descarga Exitosa!'
                            : isError
                                ? 'Fallo en la Operación'
                                : isProcessing
                                    ? 'Procesando y combinando pistas...'
                                    : 'Descargando flujo multimedia...',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDone
                              ? theme.colorScheme.tertiary
                              : isError
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurface,
                        ),
                      ),
                      if (widget.progress.currentStep != null && !isDone && !isError) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.progress.currentStep!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (!isDone && !isError)
                  OutlinedButton.icon(
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.stop_circle_outlined, size: 16),
                    label: const Text('Cancelar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(
                        color: theme.colorScheme.error.withValues(alpha: 0.6),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Contenido según estado: Activo vs Completado vs Error
            if (isError)
              _buildErrorView(context, theme)
            else if (isDone)
              _buildCompletedView(context, theme)
            else
              _buildProgressView(context, theme, isProcessing),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(
    BuildContext context,
    ThemeData theme,
    bool isDone,
    bool isError,
    bool isProcessing,
  ) {
    if (isDone) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.task_alt_rounded,
          color: theme.colorScheme.onTertiaryContainer,
          size: 24,
        ),
      );
    }

    if (isError) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.error_outline_rounded,
          color: theme.colorScheme.onErrorContainer,
          size: 24,
        ),
      );
    }

    if (isProcessing) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFFC084FC).withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
        child: const Icon(
          Icons.auto_fix_high_rounded,
          color: Color(0xFFC084FC),
          size: 24,
        ),
      );
    }

    // Estado descargando / conectando con anillo de sincronización
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final glowAlpha = 0.3 + 0.3 * math.sin(_animController.value * math.pi * 2);
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF38BDF8).withValues(alpha: glowAlpha),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.2 * glowAlpha),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(
            Icons.cloud_download_rounded,
            color: Color(0xFF38BDF8),
            size: 24,
          ),
        );
      },
    );
  }

  Widget _buildProgressView(BuildContext context, ThemeData theme, bool isProcessing) {
    final isIndeterminate = widget.progress.percentage <= 0.0 && !isProcessing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Escáner de pistas segmentado Cyberpunk (Opción 3)
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: widget.progress.percentage),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          builder: (context, animatedPercentage, _) {
            return AnimatedBuilder(
              animation: _animController,
              builder: (context, _) {
                return SizedBox(
                  height: 12,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _CyberTrackRadarPainter(
                      animationValue: _animController.value,
                      progressPercent: animatedPercentage,
                      isIndeterminate: isIndeterminate,
                      isProcessing: isProcessing,
                      primaryColor: const Color(0xFF38BDF8),
                      secondaryColor: const Color(0xFFC084FC),
                      trackBgColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                    ),
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 14),

        // Fila técnica de estado y métricas
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (isIndeterminate)
              _buildIndeterminateBadge(theme)
            else if (isProcessing)
              _buildProcessingBadge(theme)
            else
              _buildDeterminateBadge(theme),

            Row(
              children: [
                if (widget.progress.speed != null && widget.progress.speed!.isNotEmpty) ...[
                  const Icon(Icons.speed_rounded, size: 14, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 5),
                  Text(
                    widget.progress.speed!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
                if (widget.progress.eta != null && widget.progress.eta!.isNotEmpty) ...[
                  const Icon(Icons.timer_outlined, size: 14, color: Color(0xFFC084FC)),
                  const SizedBox(width: 5),
                  Text(
                    'ETA: ${widget.progress.eta}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIndeterminateBadge(ThemeData theme) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, _) {
        final dotCount = ((_animController.value * 4).floor() % 4);
        final dots = '.' * (dotCount == 0 ? 1 : dotCount);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1929).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.sensors_rounded,
                size: 13,
                color: Color(0xFF38BDF8),
              ),
              const SizedBox(width: 6),
              Text(
                'ESCANEANDO STREAM $dots',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Color(0xFF38BDF8),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProcessingBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1028).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFFC084FC).withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_fix_high_rounded,
            size: 13,
            color: Color(0xFFC084FC),
          ),
          SizedBox(width: 6),
          Text(
            'COMBINANDO PISTAS FFMPEG',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: Color(0xFFC084FC),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeterminateBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Text(
        '[ ${widget.progress.percentage.toStringAsFixed(1)} % ]',
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildCompletedView(BuildContext context, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.tertiary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'El archivo está listo y guardado en tu carpeta de descargas.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
                if (widget.progress.outputFilePath != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.progress.outputFilePath!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (widget.onOpenFolder != null) ...[
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: widget.onOpenFolder,
              icon: const Icon(Icons.folder_open_rounded, size: 16),
              label: const Text('Abrir Carpeta'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.error.withValues(alpha: 0.4),
            ),
          ),
          child: SelectableText(
            widget.progress.errorMessage ?? 'Ocurrió un error inesperado durante el procesamiento.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.error,
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: () => _copyErrorToClipboard(
                context,
                widget.progress.errorMessage ?? 'Error desconocido',
              ),
              icon: const Icon(Icons.copy_all_rounded, size: 16),
              label: const Text('Copiar Traza'),
            ),
            if (kDebugMode) ...[
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _openTalkerScreen(context),
                icon: const Icon(Icons.terminal_rounded, size: 16),
                label: const Text('Ver Consola de Logs'),
              ),
            ],
            if (widget.onRetry != null) ...[
              const Spacer(),
              FilledButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Pintor personalizado para el Escáner de Pistas Cyberpunk (Opción 3).
/// Dibuja segmentos con esquinas redondeadas y animación fluida de radar / avance.
class _CyberTrackRadarPainter extends CustomPainter {
  final double animationValue;
  final double progressPercent; // 0.0 to 100.0
  final bool isIndeterminate;
  final bool isProcessing;
  final Color primaryColor;
  final Color secondaryColor;
  final Color trackBgColor;

  _CyberTrackRadarPainter({
    required this.animationValue,
    required this.progressPercent,
    required this.isIndeterminate,
    required this.isProcessing,
    required this.primaryColor,
    required this.secondaryColor,
    required this.trackBgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const int totalSegments = 28;
    const double gap = 3.5;
    final double segmentWidth = (size.width - (totalSegments - 1) * gap) / totalSegments;
    final double segmentHeight = size.height;
    const Radius cornerRadius = Radius.circular(2.5);

    final Paint bgPaint = Paint()..color = trackBgColor;

    if (isIndeterminate) {
      // Escaneo fluido de izquierda a derecha estilo radar con halo de caída
      final double sweepPos = animationValue * (totalSegments + 6) - 3;
      const double beamRadius = 3.8;

      for (int i = 0; i < totalSegments; i++) {
        final double x = i * (segmentWidth + gap);
        final RRect rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, segmentWidth, segmentHeight),
          cornerRadius,
        );

        final double dist = (i - sweepPos).abs();
        if (dist <= beamRadius) {
          final double intensity = (1.0 - (dist / beamRadius)).clamp(0.0, 1.0);
          final double smoothIntensity = Curves.easeOutQuad.transform(intensity);

          final Color activeColor = Color.lerp(
            const Color(0xFF38BDF8), // Cian eléctrico
            const Color(0xFFC084FC), // Violeta neón
            (i / totalSegments).clamp(0.0, 1.0),
          )!;

          final Color segColor = Color.lerp(trackBgColor, activeColor, smoothIntensity)!;

          if (smoothIntensity > 0.45) {
            final Paint glowPaint = Paint()
              ..color = activeColor.withValues(alpha: 0.35 * smoothIntensity)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
            canvas.drawRRect(rect.inflate(1.5), glowPaint);
          }

          final Paint segPaint = Paint()..color = segColor;
          canvas.drawRRect(rect, segPaint);
        } else {
          canvas.drawRRect(rect, bgPaint);
        }
      }
    } else if (isProcessing) {
      // Multiplexado FFmpeg: onda armónica magenta/rosa
      final double wavePos = animationValue * (totalSegments + 4) - 2;
      for (int i = 0; i < totalSegments; i++) {
        final double x = i * (segmentWidth + gap);
        final RRect rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, segmentWidth, segmentHeight),
          cornerRadius,
        );

        final double dist = (i - wavePos).abs();
        final double waveFactor = dist <= 4.0 ? (1.0 - dist / 4.0) : 0.0;
        final Color activeColor = Color.lerp(
          secondaryColor,
          const Color(0xFFFB7185), // Rosa neón
          (i / totalSegments).clamp(0.0, 1.0),
        )!;

        final Color segColor = Color.lerp(
          activeColor.withValues(alpha: 0.5),
          activeColor,
          waveFactor,
        )!;

        final Paint segPaint = Paint()..color = segColor;
        canvas.drawRRect(rect, segPaint);
      }
    } else {
      // Avance porcentual determinado
      final double filledRatio = (progressPercent / 100.0).clamp(0.0, 1.0);
      final double activeSegmentFloat = filledRatio * totalSegments;
      final int filledCount = activeSegmentFloat.floor();

      for (int i = 0; i < totalSegments; i++) {
        final double x = i * (segmentWidth + gap);
        final RRect rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, segmentWidth, segmentHeight),
          cornerRadius,
        );

        if (i < filledCount) {
          final double t = (i / totalSegments).clamp(0.0, 1.0);
          final Color segColor = Color.lerp(
            const Color(0xFF38BDF8),
            const Color(0xFFC084FC),
            t,
          )!;
          canvas.drawRRect(rect, Paint()..color = segColor);
        } else if (i == filledCount && filledCount < totalSegments) {
          final double partial = activeSegmentFloat - filledCount;
          final double pulse = 0.6 + 0.4 * math.sin(animationValue * math.pi * 2);
          final Color activeColor = Color.lerp(
            const Color(0xFF38BDF8),
            const Color(0xFFC084FC),
            (i / totalSegments).clamp(0.0, 1.0),
          )!;

          final Color segColor = activeColor.withValues(
            alpha: (partial * pulse).clamp(0.35, 1.0),
          );

          final Paint glowPaint = Paint()
            ..color = activeColor.withValues(alpha: 0.35 * pulse)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
          canvas.drawRRect(rect.inflate(2), glowPaint);

          canvas.drawRRect(rect, Paint()..color = segColor);
        } else {
          canvas.drawRRect(rect, bgPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CyberTrackRadarPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.progressPercent != progressPercent ||
        oldDelegate.isIndeterminate != isIndeterminate ||
        oldDelegate.isProcessing != isProcessing;
  }
}
