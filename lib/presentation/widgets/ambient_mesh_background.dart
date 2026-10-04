import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Fondo ambiental dinámico con auroras flotantes y efecto Mesh Gradient.
/// Renderiza esferas de luz difusa en movimiento orgánico aceleradas por GPU a 60-120 FPS
/// sobre una base oscura profunda (#0B0B10) sin velos blanquecinos ni rejillas opacas.
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
    return Stack(
      fit: StackFit.expand,
      children: [
        // Capa de fondo base ultra oscuro (#0B0B10)
        const Positioned.fill(
          child: ColoredBox(
            color: Color(0xFF0B0B10),
          ),
        ),

        // Capa de Auroras / Mesh Gradients animados y coloridos (Púrpura, Cian, Rosa, Azul)
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

        // Contenido interactivo principal
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
    const double baseAlpha = 0.18;

    // Orbe 1: Violeta Neón (Superior Izquierda)
    final Offset center1 = Offset(
      size.width * (0.20 + 0.12 * math.sin(t)),
      size.height * (0.18 + 0.10 * math.cos(t)),
    );
    final double radius1 = math.max(size.width, size.height) * 0.45;
    _drawGlowingOrb(
      canvas,
      center1,
      radius1,
      const Color(0xFF8B5CF6),
      baseAlpha * 1.15,
    );

    // Orbe 2: Cian Eléctrico (Superior Derecha / Centro)
    final Offset center2 = Offset(
      size.width * (0.82 - 0.14 * math.cos(t * 1.2)),
      size.height * (0.32 + 0.12 * math.sin(t * 1.2)),
    );
    final double radius2 = math.max(size.width, size.height) * 0.48;
    _drawGlowingOrb(
      canvas,
      center2,
      radius2,
      const Color(0xFF06B6D4),
      baseAlpha * 1.05,
    );

    // Orbe 3: Magenta / Rosa Neón (Inferior Izquierda)
    final Offset center3 = Offset(
      size.width * (0.28 + 0.12 * math.cos(t * 0.8 + 1)),
      size.height * (0.82 - 0.10 * math.sin(t * 0.8 + 1)),
    );
    final double radius3 = math.max(size.width, size.height) * 0.40;
    _drawGlowingOrb(
      canvas,
      center3,
      radius3,
      const Color(0xFFEC4899),
      baseAlpha * 0.95,
    );

    // Orbe 4: Azul Cobalto Neón (Inferior Derecha)
    final Offset center4 = Offset(
      size.width * (0.78 + 0.10 * math.sin(t * 1.1 + 2)),
      size.height * (0.80 - 0.08 * math.cos(t * 1.1 + 2)),
    );
    final double radius4 = math.max(size.width, size.height) * 0.46;
    _drawGlowingOrb(
      canvas,
      center4,
      radius4,
      const Color(0xFF3B82F6),
      baseAlpha * 1.05,
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
