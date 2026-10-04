import 'package:flutter/material.dart';

/// Shimmer de carga esquelética para el análisis previo de URLs.
/// Utiliza un gradiente lineal animado con [AnimationController] nativo,
/// evitando dependencias externas y respetando los colores del tema M3.
class MediaPreviewSkeleton extends StatefulWidget {
  const MediaPreviewSkeleton({super.key});

  @override
  State<MediaPreviewSkeleton> createState() => _MediaPreviewSkeletonState();
}

class _MediaPreviewSkeletonState extends State<MediaPreviewSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _animation = Tween<double>(begin: -1.5, end: 1.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final highlightColor = theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.9);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final gradient = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.1, 0.5, 0.9],
          colors: [baseColor, highlightColor, baseColor],
          transform: _SlideGradientTransform(_animation.value),
        );

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Miniatura esquelética (16:9)
                Container(
                  width: 200,
                  height: 115,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: gradient,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.play_circle_outline_rounded,
                      size: 36,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Líneas de texto y metadatos simulados
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 18,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: gradient,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 220,
                        height: 14,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: gradient,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: gradient,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 120,
                            height: 12,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: gradient,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: 160,
                        height: 22,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: gradient,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SlideGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlideGradientTransform(this.slidePercent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0.0, 0.0);
  }
}
