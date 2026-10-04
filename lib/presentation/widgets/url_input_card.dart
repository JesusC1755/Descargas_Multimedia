import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tarjeta de entrada y captura de URL con diseño ergonómico de escritorio y adaptabilidad móvil.
/// Incluye atajos de teclado, limpieza instantánea, integración de portapapeles y estados tonales.
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
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      controller.text = data.text!.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 18),
              SizedBox(width: 8),
              Text('Enlace pegado desde el portapapeles'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 580;

        return Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
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
                      'Dirección URL del contenido',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (!isCompact)
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(context, theme),
                      ),
                      const SizedBox(width: 10),
                      _buildPasteButton(context, theme),
                      const SizedBox(width: 10),
                      _buildAnalyzeButton(context, theme),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTextField(context, theme),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _buildPasteButton(context, theme)),
                          const SizedBox(width: 10),
                          Expanded(child: _buildAnalyzeButton(context, theme)),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextField(BuildContext context, ThemeData theme) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          enabled: !isLoading,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: 'Ej. https://www.youtube.com/watch?v=...',
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerLowest,
            prefixIcon: Icon(
              Icons.search_rounded,
              color: theme.colorScheme.primary,
            ),
            suffixIcon: value.text.isNotEmpty
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
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 1.8,
              ),
            ),
          ),
          onSubmitted: (_) {
            if (!isLoading) onAnalyze();
          },
        );
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

  Widget _buildAnalyzeButton(BuildContext context, ThemeData theme) {
    return Tooltip(
      message: 'Consultar formatos y resoluciones disponibles',
      child: FilledButton.icon(
        onPressed: isLoading ? null : onAnalyze,
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
          elevation: 1,
        ),
      ),
    );
  }
}
