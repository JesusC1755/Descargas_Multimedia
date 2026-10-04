import 'package:flutter/material.dart';

/// Estado vacío ilustrativo que orienta al usuario cuando aún no se ha analizado ninguna URL.
/// Muestra plataformas soportadas, atajos rápidos y estética M3 tonal.
class EmptyStateCard extends StatelessWidget {
  final VoidCallback onPasteFromClipboard;

  const EmptyStateCard({
    super.key,
    required this.onPasteFromClipboard,
  });

  static const List<_PlatformTag> _supportedPlatforms = [
    _PlatformTag(name: 'YouTube', icon: Icons.smart_display_rounded),
    _PlatformTag(name: 'TikTok', icon: Icons.music_video_rounded),
    _PlatformTag(name: 'Instagram', icon: Icons.camera_alt_rounded),
    _PlatformTag(name: 'Twitter / X', icon: Icons.tag_rounded),
    _PlatformTag(name: 'SoundCloud', icon: Icons.graphic_eq_rounded),
    _PlatformTag(name: 'Twitch', icon: Icons.videogame_asset_rounded),
    _PlatformTag(name: 'Vimeo', icon: Icons.movie_filter_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.file_download_outlined,
                size: 40,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Listo para descargar multimedia',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                'Ingresa o pega un enlace para obtener resoluciones de video en alta definición (hasta 4K) o pistas de audio puras (MP3, M4A, FLAC).',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: onPasteFromClipboard,
              icon: const Icon(Icons.content_paste_go_rounded, size: 18),
              label: const Text('Pegar desde el portapapeles'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Divider(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Text(
                    'PLATAFORMAS POPULARES SOPORTADAS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: _supportedPlatforms.map((platform) {
                return Chip(
                  avatar: Icon(
                    platform.icon,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  label: Text(platform.name),
                  labelStyle: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  backgroundColor: theme.colorScheme.surfaceContainerLow,
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformTag {
  final String name;
  final IconData icon;

  const _PlatformTag({required this.name, required this.icon});
}
