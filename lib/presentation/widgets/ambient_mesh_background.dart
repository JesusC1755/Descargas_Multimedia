import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Fondo ambiental dinámico con pipelines paralelos de descarga multimedia (Dual Track Stream).
/// Renderiza en GPU haces de flujo descendente:
/// - Pista izquierda: Pipeline de Video MP4 en Cian Neón (#38BDF8 / #06B6D4) con micro-tags (4K, 1080p, AV1, 60 FPS).
/// - Pista derecha: Pipeline de Audio Master en Fucsia/Rosa Neón (#FB7185 / #E11D48) con micro-tags (320 kbps, FLAC, 48 kHz).
/// - Zona central: Base oscura profunda (#08080D) que realza el contraste y los bordes iluminados de las tarjetas.
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
      duration: const Duration(seconds: 14),
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
        // Capa de fondo base oscura profunda
        const Positioned.fill(
          child: ColoredBox(
            color: Color(0xFF08080D),
          ),
        ),

        // Capa animada de Dual Track Stream
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _DualTrackStreamPainter(progress: _controller.value),
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

/// Renderizador CustomPainter para el fondo Dual Track Stream.
class _DualTrackStreamPainter extends CustomPainter {
  final double progress;

  _DualTrackStreamPainter({required this.progress});

  static const _videoTags = ['4K UHD', '1080p', '60 FPS', 'AV1', 'H.264', 'MP4'];
  static const _audioTags = ['320 kbps', 'FLAC', '48 kHz', 'STEREO', 'MP3', 'OPUS'];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final double maxDim = math.max(size.width, size.height);

    // Halo dual cenital: Cian sutil hacia la izquierda, Violeta/Fucsia hacia la derecha
    final Paint leftGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF0284C7).withValues(alpha: 0.15),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(size.width * 0.20, 0), radius: maxDim * 0.60));
    canvas.drawCircle(Offset(size.width * 0.20, 0), maxDim * 0.60, leftGlow);

    final Paint rightGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFE11D48).withValues(alpha: 0.12),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(size.width * 0.80, 0), radius: maxDim * 0.60));
    canvas.drawCircle(Offset(size.width * 0.80, 0), maxDim * 0.60, rightGlow);

    void drawTag(String text, Offset pos, Color color, {double alpha = 0.22}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color.withValues(alpha: alpha),
            fontSize: 9.0,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos);
    }

    // Encabezados de pista fijos en el borde superior (Y = 12)
    drawTag('// VIDEO MP4 PIPELINE', const Offset(24, 12), const Color(0xFF38BDF8), alpha: 0.35);
    drawTag('// AUDIO FLAC/MP3 PIPELINE', Offset(size.width - 180, 12), const Color(0xFFFB7185), alpha: 0.35);

    // Haces y micro-tags de Video (Izquierda: 0.03 a 0.24)
    const int videoStreams = 11;
    for (int i = 0; i < videoStreams; i++) {
      final double normX = 0.03 + (i / videoStreams) * 0.21;
      final double speed = 1.0 + (i % 3) * 0.40;
      final double phase = (i * 0.137) % 1.0;
      final double length = 100.0 + (i % 3) * 50.0;
      final double travel = (progress * speed + phase) % 1.0;
      final double totalH = size.height + length;
      final double y = travel * totalH - length;
      final double x = normX * size.width;

      final Rect lineRect = Rect.fromLTWH(x - 0.9, y, 1.8, length);
      final Paint streamPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFF38BDF8).withValues(alpha: 0.20),
            const Color(0xFF06B6D4).withValues(alpha: 0.50),
            Colors.transparent,
          ],
          stops: const [0.0, 0.40, 0.95, 1.0],
        ).createShader(lineRect);

      canvas.drawRRect(RRect.fromRectAndRadius(lineRect, const Radius.circular(1)), streamPaint);
      canvas.drawCircle(Offset(x, y + length * 0.95), 1.4, Paint()..color = Colors.white.withValues(alpha: 0.70));

      // Flotar un micro-tag cada 3 columnas por debajo del encabezado
      if (i % 3 == 1 && y > 88 && y < size.height - 40) {
        final tagText = _videoTags[(i + (travel * 4).toInt()) % _videoTags.length];
        drawTag(tagText, Offset(x + 5, y + length * 0.5), const Color(0xFF38BDF8), alpha: 0.20);
      }
    }

    // Haces y micro-tags de Audio (Derecha: 0.75 a 0.97)
    const int audioStreams = 11;
    for (int i = 0; i < audioStreams; i++) {
      final double normX = 0.75 + (i / audioStreams) * 0.22;
      final double speed = 1.1 + (i % 3) * 0.35;
      final double phase = ((i + 5) * 0.161) % 1.0;
      final double length = 95.0 + (i % 3) * 45.0;
      final double travel = (progress * speed + phase) % 1.0;
      final double totalH = size.height + length;
      final double y = travel * totalH - length;
      final double x = normX * size.width;

      final Rect lineRect = Rect.fromLTWH(x - 0.9, y, 1.8, length);
      final Paint streamPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFFFB7185).withValues(alpha: 0.20),
            const Color(0xFFE11D48).withValues(alpha: 0.50),
            Colors.transparent,
          ],
          stops: const [0.0, 0.40, 0.95, 1.0],
        ).createShader(lineRect);

      canvas.drawRRect(RRect.fromRectAndRadius(lineRect, const Radius.circular(1)), streamPaint);
      canvas.drawCircle(Offset(x, y + length * 0.95), 1.4, Paint()..color = Colors.white.withValues(alpha: 0.70));

      if (i % 3 == 1 && y > 88 && y < size.height - 40) {
        final tagText = _audioTags[(i + (travel * 4).toInt()) % _audioTags.length];
        drawTag(tagText, Offset(x + 5, y + length * 0.5), const Color(0xFFFB7185), alpha: 0.20);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DualTrackStreamPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
