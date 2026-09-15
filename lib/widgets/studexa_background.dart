import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Branded application canvas with subtle academic geometry.
///
/// The decoration is intentionally non-interactive and uses only the existing
/// Studexa palette, so screens keep their original layout and behavior.
class StudexaBackground extends StatelessWidget {
  const StudexaBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AppTheme.backgroundGradient),
        ),
        const IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(painter: _AcademicCanvasPainter()),
          ),
        ),
        child,
      ],
    );
  }
}

class _AcademicCanvasPainter extends CustomPainter {
  const _AcademicCanvasPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final softFill = Paint()
      ..color = AppTheme.primaryNavy.withValues(alpha: 0.035)
      ..style = PaintingStyle.fill;
    final faintFill = Paint()
      ..color = AppTheme.darkNavy.withValues(alpha: 0.018)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = AppTheme.primaryNavy.withValues(alpha: 0.026)
      ..strokeWidth = 1;

    canvas.drawCircle(Offset(size.width * 0.92, 72), 116, softFill);
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.74), 150, faintFill);

    const grid = 48.0;
    for (double x = 24; x < size.width; x += grid) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 24; y < size.height; y += grid) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
