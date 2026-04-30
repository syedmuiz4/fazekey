import 'package:flutter/material.dart';

class FaceGuideOverlay extends StatelessWidget {
  const FaceGuideOverlay({super.key, this.scanning = true});
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _FaceGuidePainter(scanning: scanning, color: Theme.of(context).colorScheme.primary),
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
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = color;
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: size.width * .68, height: size.height * .48);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(120)), paint);
    if (scanning) {
      final line = Paint()
        ..shader = LinearGradient(colors: [Colors.transparent, color, Colors.transparent]).createShader(rect)
        ..strokeWidth = 3;
      canvas.drawLine(Offset(rect.left + 24, rect.center.dy), Offset(rect.right - 24, rect.center.dy), line);
    }
  }

  @override
  bool shouldRepaint(covariant _FaceGuidePainter oldDelegate) => oldDelegate.scanning != scanning || oldDelegate.color != color;
}
