import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:talker_flutter/talker_flutter.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/download_progress.dart';

/// Monitor interactivo de descargas y procesamiento multimedia.
/// Incluye interpolación suave de barra de progreso con [TweenAnimationBuilder],
/// diferenciación de fases (descarga vs transcodificación FFmpeg),
/// feedback de éxito celebratorio y diagnóstico de errores integrado con Talker.
class DownloadProgressCard extends StatelessWidget {
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
    final isDone = progress.status == DownloadStatus.completed;
    final isError = progress.status == DownloadStatus.error;
    final isProcessing = progress.status == DownloadStatus.processing ||
        (progress.currentStep?.toLowerCase().contains('ffmpeg') ?? false) ||
        (progress.currentStep?.toLowerCase().contains('uniendo') ?? false);

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
                      if (progress.currentStep != null && !isDone && !isError) ...[
                        const SizedBox(height: 2),
                        Text(
                          progress.currentStep!,
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
                    onPressed: onCancel,
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
        ),
        child: Icon(
          Icons.auto_fix_high_rounded,
          color: theme.colorScheme.onSecondaryContainer,
          size: 24,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.cloud_download_rounded,
        color: theme.colorScheme.onPrimaryContainer,
        size: 24,
      ),
    );
  }

  Widget _buildProgressView(BuildContext context, ThemeData theme, bool isProcessing) {
    final targetValue = (progress.percentage / 100.0).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: targetValue),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            builder: (context, animatedValue, _) {
              if (isProcessing && animatedValue >= 0.99) {
                return LinearProgressIndicator(
                  minHeight: 10,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.secondary),
                );
              }
              return LinearProgressIndicator(
                value: animatedValue,
                minHeight: 10,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${progress.percentage.toStringAsFixed(1)} %',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            Row(
              children: [
                if (progress.speed != null && progress.speed!.isNotEmpty) ...[
                  Icon(Icons.speed_rounded, size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    progress.speed!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                if (progress.eta != null && progress.eta!.isNotEmpty) ...[
                  Icon(Icons.timer_outlined, size: 14, color: theme.colorScheme.secondary),
                  const SizedBox(width: 4),
                  Text(
                    'ETA: ${progress.eta}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
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
                if (progress.outputFilePath != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    progress.outputFilePath!,
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
          if (onOpenFolder != null) ...[
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: onOpenFolder,
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
            progress.errorMessage ?? 'Ocurrió un error inesperado durante el procesamiento.',
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
                progress.errorMessage ?? 'Error desconocido',
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
            if (onRetry != null) ...[
              const Spacer(),
              FilledButton.icon(
                onPressed: onRetry,
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
