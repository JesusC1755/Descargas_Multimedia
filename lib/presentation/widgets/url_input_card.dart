import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/media_url_validator.dart';

/// Tarjeta de entrada y captura de URL con validación de fuentes de video en tiempo real.
/// Restringe el análisis a plataformas multimedia soportadas y archivos directos,
/// proveyendo retroalimentación visual inmediata antes de invocar subprocesos.
class UrlInputCard extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onAnalyze;

  const UrlInputCard({
    super.key,
    required this.controller,
    required this.isLoading,
    required this.onAnalyze,
  });

  Future<void> _pasteFromClipboard(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;

    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;

    final validation = MediaUrlValidator.validate(text);
    if (validation.isValid && validation.cleanUrl != null) {
      controller.text = validation.cleanUrl!;
    } else {
      controller.text = text;
    }

    final theme = Theme.of(context);
    if (validation.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(validation.platform.icon, size: 18, color: theme.colorScheme.onPrimaryContainer),
              const SizedBox(width: 8),
              Text('Enlace de ${validation.platformDisplayName} pegado'),
            ],
          ),
          backgroundColor: theme.colorScheme.primaryContainer,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: theme.colorScheme.errorContainer,
          content: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'El enlace pegado no corresponde a un video compatible.',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final text = value.text.trim();
        final validation = text.isNotEmpty ? MediaUrlValidator.validate(text) : null;
        final bool canAnalyze = !isLoading && (validation?.isValid ?? false);

        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 620;

            return Card(
              elevation: 1,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: validation != null && !validation.isValid
                      ? theme.colorScheme.error.withValues(alpha: 0.4)
                      : theme.colorScheme.outline.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.link_rounded,
                            size: 18,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Dirección URL del video',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const Spacer(),
                        if (validation != null && validation.isValid)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(validation.platform.icon, size: 14, color: theme.colorScheme.primary),
                                const SizedBox(width: 5),
                                Text(
                                  validation.platformDisplayName ?? '',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (!isCompact)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildTextField(context, theme, validation),
                          ),
                          const SizedBox(width: 10),
                          _buildPasteButton(context, theme),
                          const SizedBox(width: 10),
                          _buildAnalyzeButton(context, theme, canAnalyze: canAnalyze),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTextField(context, theme, validation),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: _buildPasteButton(context, theme)),
                              const SizedBox(width: 10),
                              Expanded(child: _buildAnalyzeButton(context, theme, canAnalyze: canAnalyze)),
                            ],
                          ),
                        ],
                      ),

                    // Mensaje informativo o de advertencia si la URL no es un video compatible
                    if (validation != null && !validation.isValid) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.error.withValues(alpha: 0.3),
                            width: 1.1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                validation.errorMessage ?? 'Este enlace no corresponde a un video compatible.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTextField(
    BuildContext context,
    ThemeData theme,
    MediaUrlValidationResult? validation,
  ) {
    final bool hasError = validation != null && !validation.isValid;

    return TextField(
      controller: controller,
      enabled: !isLoading,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: 'Ej. https://www.youtube.com/watch?v=... o https://tiktok.com/@...',
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerLowest,
        prefixIcon: Icon(
          validation != null && validation.isValid
              ? validation.platform.icon
              : Icons.search_rounded,
          color: hasError
              ? theme.colorScheme.error
              : validation != null && validation.isValid
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
        ),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                tooltip: 'Limpiar campo',
                icon: const Icon(Icons.clear_rounded, size: 20),
                onPressed: isLoading ? null : () => controller.clear(),
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: hasError
                ? theme.colorScheme.error
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: hasError
                ? theme.colorScheme.error.withValues(alpha: 0.6)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: hasError ? theme.colorScheme.error : theme.colorScheme.primary,
            width: 1.8,
          ),
        ),
      ),
      onSubmitted: (_) {
        if (!isLoading && validation != null && validation.isValid) {
          onAnalyze();
        }
      },
    );
  }

  Widget _buildPasteButton(BuildContext context, ThemeData theme) {
    return Tooltip(
      message: 'Pegar enlace del portapapeles del sistema',
      child: OutlinedButton.icon(
        onPressed: isLoading ? null : () => _pasteFromClipboard(context),
        icon: const Icon(Icons.content_paste_rounded, size: 18),
        label: const Text('Pegar'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyzeButton(
    BuildContext context,
    ThemeData theme, {
    required bool canAnalyze,
  }) {
    final String tooltipMessage = canAnalyze
        ? 'Consultar formatos y resoluciones disponibles'
        : 'Ingresa un enlace de video compatible para analizar';

    return Tooltip(
      message: tooltipMessage,
      child: FilledButton.icon(
        onPressed: canAnalyze ? onAnalyze : null,
        icon: isLoading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: theme.colorScheme.onPrimary,
                ),
              )
            : const Icon(Icons.auto_awesome_rounded, size: 18),
        label: Text(isLoading ? 'Analizando...' : 'Analizar'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: canAnalyze ? 1 : 0,
        ),
      ),
    );
  }
}
