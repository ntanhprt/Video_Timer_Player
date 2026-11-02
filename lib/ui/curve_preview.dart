import 'package:flutter/material.dart';

import '../core/volume_curve.dart';

/// Draws the volume ramp of [spec] using the same [volumeAt] the player uses.
class CurvePreview extends StatelessWidget {
  final VolumeSpec spec;
  const CurvePreview({super.key, required this.spec});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 90,
      width: double.infinity,
      child: CustomPaint(painter: _CurvePainter(spec, scheme.primary, scheme.outlineVariant)),
    );
  }
}

class _CurvePainter extends CustomPainter {
  final VolumeSpec spec;
  final Color line;
  final Color frame;
  _CurvePainter(this.spec, this.line, this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()
      ..style = PaintingStyle.stroke
      ..color = frame);
    // Show the ramp plus a short plateau so the "hold at target" part is visible.
    final span = spec.ramp.inMilliseconds <= 0 ? const Duration(seconds: 10) : spec.ramp * 1.25;
    final path = Path();
    const steps = 60;
    for (var i = 0; i <= steps; i++) {
      final v = volumeAt(spec, span * (i / steps));
      final p = Offset(size.width * i / steps, size.height * (1 - v));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = line);
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.spec != spec || old.line != line;
}
