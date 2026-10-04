import 'package:flutter/material.dart';
import '../../domain/models/download_progress.dart';

class DownloadProgressCard extends StatelessWidget {
  final DownloadProgress progress;
  final VoidCallback onCancel;

  const DownloadProgressCard({
    super.key,
    required this.progress,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDone = progress.status == DownloadStatus.completed;
    final isError = progress.status == DownloadStatus.error;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDone
              ? Colors.green.withValues(alpha: 0.6)
              : isError
                  ? theme.colorScheme.error.withValues(alpha: 0.6)
                  : theme.colorScheme.primary.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isDone
                      ? Icons.check_circle_rounded
                      : isError
                          ? Icons.error_rounded
                          : Icons.downloading_rounded,
                  color: isDone
                      ? Colors.green
                      : isError
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isDone
                        ? '¡Descarga Finalizada!'
                        : isError
                            ? 'Error en la descarga'
                            : progress.currentStep ?? 'Descargando contenido...',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDone
                          ? Colors.green
                          : isError
                              ? theme.colorScheme.error
                              : null,
                    ),
                  ),
                ),
                if (!isDone && !isError)
                  OutlinedButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Cancelar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (!isError) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: isDone ? 1.0 : (progress.percentage / 100.0).clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDone ? Colors.green : theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Progreso: ${progress.percentage.toStringAsFixed(1)}%',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (progress.speed != null)
                    Text(
                      'Velocidad: ${progress.speed}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (progress.eta != null)
                    Text(
                      'ETA: ${progress.eta}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ] else ...[
              Text(
                progress.errorMessage ?? 'Ocurrió un error inesperado al procesar el enlace.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
