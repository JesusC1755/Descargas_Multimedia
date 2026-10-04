import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Fondo ambiental dinámico con auroras flotantes y efecto Mesh Gradient.
/// Renderiza esferas de luz difusa en movimiento orgánico aceleradas por GPU a 60-120 FPS
/// sobre una base oscura profunda (#08080C) con colores ricos y vibrantes
/// (Violeta Neón, Cian Eléctrico, Magenta, Azul Cobalto e Índigo).
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
      duration: const Duration(seconds: 22),
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
        // Capa de fondo base ultra oscuro profundo (#08080C)
        const Positioned.fill(
          child: ColoredBox(
            color: Color(0xFF08080C),
          ),
        ),

        // Capa de Auroras / Mesh Gradients animados y coloridos
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
    const double baseAlpha = 0.28;

    // Orbe 1: Violeta Neón / Púrpura (Superior Izquierda)
    final Offset center1 = Offset(
      size.width * (0.16 + 0.12 * math.sin(t)),
      size.height * (0.14 + 0.10 * math.cos(t)),
    );
    final double radius1 = math.max(size.width, size.height) * 0.50;
    _drawGlowingOrb(
      canvas,
      center1,
      radius1,
      const Color(0xFF9333EA),
      baseAlpha * 1.25,
    );

    // Orbe 2: Cian Eléctrico Neón (Superior Derecha / Centro)
    final Offset center2 = Offset(
      size.width * (0.84 - 0.14 * math.cos(t * 1.2)),
      size.height * (0.28 + 0.12 * math.sin(t * 1.2)),
    );
    final double radius2 = math.max(size.width, size.height) * 0.52;
    _drawGlowingOrb(
      canvas,
      center2,
      radius2,
      const Color(0xFF06B6D4),
      baseAlpha * 1.15,
    );

    // Orbe 3: Magenta / Rosa Neón (Inferior Izquierda)
    final Offset center3 = Offset(
      size.width * (0.25 + 0.14 * math.cos(t * 0.85 + 1)),
      size.height * (0.82 - 0.10 * math.sin(t * 0.85 + 1)),
    );
    final double radius3 = math.max(size.width, size.height) * 0.44;
    _drawGlowingOrb(
      canvas,
      center3,
      radius3,
      const Color(0xFFEC4899),
      baseAlpha * 1.10,
    );

    // Orbe 4: Azul Cobalto Neón (Inferior Derecha)
    final Offset center4 = Offset(
      size.width * (0.80 + 0.12 * math.sin(t * 1.1 + 2)),
      size.height * (0.82 - 0.08 * math.cos(t * 1.1 + 2)),
    );
    final double radius4 = math.max(size.width, size.height) * 0.48;
    _drawGlowingOrb(
      canvas,
      center4,
      radius4,
      const Color(0xFF3B82F6),
      baseAlpha * 1.20,
    );

    // Orbe 5: Índigo Luminoso Central (Fluctuación suave que une los gradientes)
    final Offset center5 = Offset(
      size.width * (0.50 + 0.10 * math.sin(t * 0.7 + 3)),
      size.height * (0.48 + 0.10 * math.cos(t * 0.7 + 3)),
    );
    final double radius5 = math.max(size.width, size.height) * 0.42;
    _drawGlowingOrb(
      canvas,
      center5,
      radius5,
      const Color(0xFF6366F1),
      baseAlpha * 0.90,
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
          color.withValues(alpha: peakAlpha * 0.55),
          color.withValues(alpha: peakAlpha * 0.18),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.38, 0.72, 1.0],
      ).createShader(rect);

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _MeshAuroraPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

