import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/media_url_validator.dart';

/// Tarjeta de entrada y captura de URL con diseño Bento y validación en tiempo real.
/// Implementa con exactitud el diseño de [design.html] y la captura proporcionada:
/// - Contenedor con gradiente oscuro y bordes ultra sutiles.
/// - Encabezado con icono violeta y badge de plataforma detectada (YouTube, etc.).
/// - Campo con tipografía monoespaciada, icono chevron púrpura y botón de limpieza.
/// - Botón "Pegar" con icono púrpura y acabado translúcido.
/// - Botón "Analizar" con gradiente horizontal vibrante (Púrpura -> Índigo -> Cian) y resplandor.
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
      final platform = validation.platform;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: platform.brandColor.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: platform.brandColor.withValues(alpha: 0.45),
                    width: 1,
                  ),
                ),
                child: Icon(
                  platform.icon,
                  size: 16,
                  color: platform == MediaPlatform.threads
                      ? Colors.white
                      : platform.brandColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    text: 'Enlace de ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                    children: [
                      TextSpan(
                        text: validation.platformDisplayName ?? platform.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: platform.badgeTextColor,
                        ),
                      ),
                      const TextSpan(text: ' pegado'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: platform.snackbarContainerColor,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: platform.brandColor.withValues(alpha: 0.45),
              width: 1.1,
            ),
          ),
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
                  color: validation != null && !validation.isValid
                      ? theme.colorScheme.error.withValues(alpha: 0.4)
                      : (validation != null && validation.isValid
                          ? validation.platform.brandColor.withValues(alpha: 0.28)
                          : Colors.white.withValues(alpha: 0.08)),
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
                    // Fila de Encabezado: Icono, Título e Indicador de Plataforma
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFF9333EA).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFFA855F7).withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.link_rounded,
                            size: 16,
                            color: Color(0xFFC084FC),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Dirección URL del video',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF1F5F9),
                            letterSpacing: 0.1,
                          ),
                        ),
                        const Spacer(),
                        if (validation != null && validation.isValid)
                          _buildPlatformBadge(validation),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Fila de Entrada URL y Botones de Acción
                    if (!isCompact)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: _buildTextField(context, validation),
                          ),
                          const SizedBox(width: 10),
                          _buildPasteButton(context),
                          const SizedBox(width: 10),
                          _buildAnalyzeButton(canAnalyze: canAnalyze),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTextField(context, validation),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: _buildPasteButton(context)),
                              const SizedBox(width: 10),
                              Expanded(child: _buildAnalyzeButton(canAnalyze: canAnalyze)),
                            ],
                          ),
                        ],
                      ),

                    // Mensaje informativo o de advertencia si la URL no es válida
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
    MediaUrlValidationResult? validation,
  ) {
    final bool hasError = validation != null && !validation.isValid;

    return SizedBox(
      height: 46,
      child: TextField(
        controller: controller,
        enabled: !isLoading,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Pega un enlace de YouTube, Vimeo, TikTok, etc...',
          hintStyle: TextStyle(
            color: const Color(0xFF64748B),
            fontSize: 13,
            fontFamily: 'monospace',
          ),
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.45),
          prefixIcon: Icon(
            validation != null && validation.isValid
                ? validation.platform.icon
                : Icons.play_arrow_outlined,
            color: validation != null && validation.isValid
                ? (validation.platform == MediaPlatform.threads
                    ? Colors.white
                    : validation.platform.brandColor)
                : const Color(0xFFA855F7),
            size: 18,
          ),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  tooltip: 'Limpiar campo',
                  icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF94A3B8)),
                  onPressed: isLoading ? null : () => controller.clear(),
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: hasError
                  ? const Color(0xFFF87171)
                  : Colors.white.withValues(alpha: 0.09),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: hasError
                  ? const Color(0xFFF87171)
                  : Colors.white.withValues(alpha: 0.09),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: hasError
                  ? const Color(0xFFF87171)
                  : (validation != null && validation.isValid
                      ? validation.platform.brandColor.withValues(alpha: 0.8)
                      : const Color(0xFFA855F7).withValues(alpha: 0.6)),
              width: 1.5,
            ),
          ),
        ),
        onSubmitted: (_) {
          if (!isLoading && validation != null && validation.isValid) {
            onAnalyze();
          }
        },
      ),
    );
  }

  /// Insignia con el estilo y color característico de la plataforma detectada.
  Widget _buildPlatformBadge(MediaUrlValidationResult validation) {
    final platform = validation.platform;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: platform.badgeBackgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: platform.badgeBorderColor,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: platform.brandColor.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            platform.icon,
            size: 14,
            color: platform == MediaPlatform.threads
                ? Colors.white
                : platform.brandColor,
          ),
          const SizedBox(width: 6),
          Text(
            validation.platformDisplayName ?? platform.displayName,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: platform.badgeTextColor,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasteButton(BuildContext context) {
    return Tooltip(
      message: 'Pegar enlace del portapapeles',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : () => _pasteFromClipboard(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.09),
                width: 1.0,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.content_paste_rounded,
                  size: 16,
                  color: Color(0xFFA855F7),
                ),
                SizedBox(width: 8),
                Text(
                  'Pegar',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFE2E8F0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyzeButton({
    required bool canAnalyze,
  }) {
    final String tooltipMessage = canAnalyze
        ? 'Consultar formatos y resoluciones disponibles'
        : 'Ingresa un enlace de video compatible para analizar';

    return Tooltip(
      message: tooltipMessage,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 46,
        decoration: BoxDecoration(
          gradient: canAnalyze
              ? const LinearGradient(
                  colors: [
                    Color(0xFF9333EA),
                    Color(0xFF6366F1),
                    Color(0xFF06B6D4),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: canAnalyze
              ? null
              : const Color(0xFF262638).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: canAnalyze
              ? Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1.0,
                )
              : null,
          boxShadow: canAnalyze
              ? [
                  BoxShadow(
                    color: const Color(0xFF06B6D4).withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: canAnalyze ? onAnalyze : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isLoading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: Color(0xFFE0F2FE),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    isLoading ? 'Analizando...' : 'Analizar',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: canAnalyze
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
      ),
    );
  }
}
