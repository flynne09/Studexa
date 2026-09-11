import 'package:flutter/material.dart';

/// Renders the official multi-colored Google 'G' icon using vector paths.
///
/// Designed to be self-contained, high-resolution at any scale, and require no
/// external assets or network requests.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: const _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  // Canonical Google brand colors
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    // Original SVG coordinate space is 48x48
    final scale = size.width / 48.0;
    canvas.save();
    canvas.scale(scale, scale);

    final paint = Paint()..style = PaintingStyle.fill;

    // 1. Blue segment (Crossbar and right lower edge)
    paint.color = _blue;
    final bluePath = Path()
      ..moveTo(43.611, 20.083)
      ..lineTo(42.0, 20.0)
      ..lineTo(24.0, 20.0)
      ..lineTo(24.0, 28.0)
      ..lineTo(35.303, 28.0)
      ..cubicTo(34.468, 30.373, 32.969, 32.404, 31.0, 33.784)
      ..lineTo(37.472, 38.76)
      ..cubicTo(41.22, 35.303, 44.0, 30.138, 44.0, 24.0)
      ..cubicTo(44.0, 22.659, 43.862, 21.35, 43.611, 20.083)
      ..close();
    canvas.drawPath(bluePath, paint);

    // 2. Green segment (Bottom arc)
    paint.color = _green;
    final greenPath = Path()
      ..moveTo(24.0, 44.0)
      ..cubicTo(29.403, 44.0, 34.023, 42.213, 37.472, 38.76)
      ..lineTo(31.0, 33.784)
      ..cubicTo(29.176, 35.006, 26.786, 35.75, 24.0, 35.75)
      ..cubicTo(18.736, 35.75, 14.225, 32.186, 12.632, 27.38)
      ..lineTo(5.957, 32.543)
      ..cubicTo(9.387, 39.351, 16.326, 44.0, 24.0, 44.0)
      ..close();
    canvas.drawPath(greenPath, paint);

    // 3. Yellow segment (Left lower arc)
    paint.color = _yellow;
    final yellowPath = Path()
      ..moveTo(12.632, 27.38)
      ..cubicTo(12.227, 26.166, 12.0, 24.863, 12.0, 23.5)
      ..cubicTo(12.0, 22.137, 12.227, 20.834, 12.632, 19.62)
      ..lineTo(5.957, 14.457)
      ..cubicTo(4.717, 16.918, 4.0, 19.67, 4.0, 22.5)
      ..cubicTo(4.0, 25.33, 4.717, 28.082, 5.957, 30.543)
      ..lineTo(12.632, 27.38)
      ..close();
    canvas.drawPath(yellowPath, paint);

    // 4. Red segment (Top arc)
    paint.color = _red;
    final redPath = Path()
      ..moveTo(24.0, 11.25)
      ..cubicTo(26.945, 11.25, 29.588, 12.26, 31.666, 13.924)
      ..lineTo(37.604, 7.986)
      ..cubicTo(33.992, 4.622, 29.355, 2.5, 24.0, 2.5)
      ..cubicTo(16.326, 2.5, 9.387, 7.149, 5.957, 13.957)
      ..lineTo(12.632, 19.12)
      ..cubicTo(14.225, 14.314, 18.736, 10.75, 24.0, 10.75)
      ..close();
    canvas.drawPath(redPath, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
