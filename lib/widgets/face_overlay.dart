import 'package:flutter/material.dart';

class FaceGuideOverlay extends StatelessWidget {
  const FaceGuideOverlay({super.key, this.scanning = true});
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _FaceGuidePainter(
          scanning: scanning,
          color: Theme.of(context).colorScheme.primary,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _FaceGuidePainter extends CustomPainter {
  _FaceGuidePainter({required this.scanning, required this.color});
  final bool scanning;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = color;
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width * .82,
      height: size.height * .56,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(120)),
      paint,
    );
    if (scanning) {
      final line = Paint()
        ..shader = LinearGradient(
          colors: [Colors.transparent, color, Colors.transparent],
        ).createShader(rect)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(rect.left + 30, rect.center.dy),
        Offset(rect.right - 30, rect.center.dy),
        line,
      );
      canvas.drawLine(
        Offset(rect.left + 46, rect.top + rect.height * .32),
        Offset(rect.right - 46, rect.top + rect.height * .32),
        line,
      );
      canvas.drawLine(
        Offset(rect.left + 46, rect.bottom - rect.height * .32),
        Offset(rect.right - 46, rect.bottom - rect.height * .32),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FaceGuidePainter oldDelegate) =>
      oldDelegate.scanning != scanning || oldDelegate.color != color;
}
