import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Fondo ambiental dinámico con efecto Mesh Gradient / Auroras flotantes.
/// Renderiza esferas de luz difusa en movimiento orgánico a 60-120 FPS
/// utilizando un [CustomPainter] acelerado por GPU y [RepaintBoundary].
class AmbientMeshBackground extends StatefulWidget {
  final Widget child;

  const AmbientMeshBackground({
    super.key,
    required this.child,
  });

  @override
  State<AmbientMeshBackground> createState() => _AmbientMeshBackgroundState();
}

class _AmbientMeshBackgroundState extends State<AmbientMeshBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        // Capa de fondo sólido base
        Positioned.fill(
          child: Container(
            color: theme.scaffoldBackgroundColor,
          ),
        ),

        // Capa de Auroras / Mesh Gradients animados
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _MeshAuroraPainter(
                    progress: _controller.value,
                  ),
                );
              },
            ),
          ),
        ),

        // Contenido interactivo de la pantalla
        widget.child,
      ],
    );
  }
}

class _MeshAuroraPainter extends CustomPainter {
  final double progress;

  _MeshAuroraPainter({
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final double t = progress * 2 * math.pi;
    const double baseAlpha = 0.16;

    // Orbe 1: Violeta Neón (Superior Izquierda flotante)
    final Offset center1 = Offset(
      size.width * (0.20 + 0.12 * math.sin(t)),
      size.height * (0.18 + 0.10 * math.cos(t)),
    );
    final double radius1 = math.max(size.width, size.height) * 0.42;
    _drawGlowingOrb(
      canvas,
      center1,
      radius1,
      const Color(0xFF8B5CF6),
      baseAlpha * 1.1,
    );

    // Orbe 2: Cian Eléctrico (Superior Derecha / Centro)
    final Offset center2 = Offset(
      size.width * (0.82 - 0.14 * math.cos(t * 1.2)),
      size.height * (0.32 + 0.12 * math.sin(t * 1.2)),
    );
    final double radius2 = math.max(size.width, size.height) * 0.46;
    _drawGlowingOrb(
      canvas,
      center2,
      radius2,
      const Color(0xFF06B6D4),
      baseAlpha * 1.0,
    );

    // Orbe 3: Magenta / Rosa Neón (Inferior Izquierda)
    final Offset center3 = Offset(
      size.width * (0.28 + 0.12 * math.cos(t * 0.8 + 1)),
      size.height * (0.82 - 0.10 * math.sin(t * 0.8 + 1)),
    );
    final double radius3 = math.max(size.width, size.height) * 0.38;
    _drawGlowingOrb(
      canvas,
      center3,
      radius3,
      const Color(0xFFEC4899),
      baseAlpha * 0.9,
    );

    // Orbe 4: Azul Cobalto Neón (Inferior Derecha)
    final Offset center4 = Offset(
      size.width * (0.78 + 0.10 * math.sin(t * 1.1 + 2)),
      size.height * (0.80 - 0.08 * math.cos(t * 1.1 + 2)),
    );
    final double radius4 = math.max(size.width, size.height) * 0.44;
    _drawGlowingOrb(
      canvas,
      center4,
      radius4,
      const Color(0xFF3B82F6),
      baseAlpha * 1.0,
    );
  }

  void _drawGlowingOrb(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double peakAlpha,
  ) {
    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    final Paint paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: peakAlpha),
          color.withValues(alpha: peakAlpha * 0.45),
          color.withValues(alpha: peakAlpha * 0.12),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.40, 0.70, 1.0],
      ).createShader(rect);

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _MeshAuroraPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
