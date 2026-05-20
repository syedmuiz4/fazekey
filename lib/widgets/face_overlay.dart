import 'package:flutter/material.dart';

import 'corporate_chrome.dart';

class FaceGuideOverlay extends StatelessWidget {
  const FaceGuideOverlay({super.key, this.scanning = true});
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _FaceGuidePainter(scanning: scanning),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _FaceGuidePainter extends CustomPainter {
  _FaceGuidePainter({required this.scanning});
  final bool scanning;

  @override
  void paint(Canvas canvas, Size size) {
    const teal = CorporateColors.teal;
    const gridBlue = Color(0xFF7DD3FC);
    final guideRect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width * .82,
      height: size.height * .70,
    );
    final wirePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..color = teal;
    final finePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = gridBlue.withValues(alpha: .34);
    final axisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = teal.withValues(alpha: .58);

    final faceOval = Rect.fromCenter(
      center: guideRect.center,
      width: guideRect.width * .76,
      height: guideRect.height * .86,
    );
    canvas.drawOval(faceOval, wirePaint);

    final browY = faceOval.top + faceOval.height * .34;
    final noseTop = faceOval.top + faceOval.height * .43;
    final noseBottom = faceOval.top + faceOval.height * .62;
    final mouthY = faceOval.top + faceOval.height * .71;
    final chinY = faceOval.top + faceOval.height * .84;

    _drawDashedLine(
      canvas,
      Offset(faceOval.left + faceOval.width * .18, browY),
      Offset(faceOval.right - faceOval.width * .18, browY),
      finePaint,
    );
    _drawDashedLine(
      canvas,
      Offset(faceOval.center.dx, faceOval.top + faceOval.height * .10),
      Offset(faceOval.center.dx, chinY),
      axisPaint,
    );

    final leftEye = Offset(faceOval.left + faceOval.width * .35, browY);
    final rightEye = Offset(faceOval.left + faceOval.width * .65, browY);
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = teal;
    final haloPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = gridBlue.withValues(alpha: .24);
    for (final point in [
      leftEye,
      rightEye,
      Offset(faceOval.center.dx, noseTop),
      Offset(faceOval.center.dx, noseBottom),
      Offset(faceOval.left + faceOval.width * .42, mouthY),
      Offset(faceOval.left + faceOval.width * .58, mouthY),
    ]) {
      canvas.drawCircle(point, 4.4, haloPaint);
      canvas.drawCircle(point, 2.1, dotPaint);
    }

    final nosePath = Path()
      ..moveTo(faceOval.center.dx, noseTop)
      ..lineTo(faceOval.center.dx - faceOval.width * .055, noseBottom)
      ..lineTo(faceOval.center.dx + faceOval.width * .055, noseBottom)
      ..close();
    canvas.drawPath(nosePath, finePaint);

    final mouthRect = Rect.fromCenter(
      center: Offset(faceOval.center.dx, mouthY),
      width: faceOval.width * .28,
      height: faceOval.height * .08,
    );
    canvas.drawArc(mouthRect, .12, 2.9, false, axisPaint);

    for (var i = 1; i <= 4; i++) {
      final x = guideRect.left + guideRect.width * i / 5;
      _drawDashedLine(
        canvas,
        Offset(x, guideRect.top + 12),
        Offset(x, guideRect.bottom - 12),
        finePaint,
      );
    }
    for (var i = 1; i <= 5; i++) {
      final y = guideRect.top + guideRect.height * i / 6;
      _drawDashedLine(
        canvas,
        Offset(guideRect.left + 12, y),
        Offset(guideRect.right - 12, y),
        finePaint,
      );
    }
    _drawCornerBrackets(canvas, guideRect, wirePaint);

    if (scanning) {
      final laserY = faceOval.top + faceOval.height * .42;
      final flarePaint = Paint()
        ..color = teal.withValues(alpha: .16)
        ..strokeWidth = 18;
      final scanPaint = Paint()
        ..color = teal
        ..strokeWidth = 1.8;
      canvas.drawLine(
        Offset(faceOval.left, laserY),
        Offset(faceOval.right, laserY),
        flarePaint,
      );
      canvas.drawLine(
        Offset(faceOval.left, laserY),
        Offset(faceOval.right, laserY),
        scanPaint,
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dash = 3.0;
    const gap = 5.0;
    final distance = (end - start).distance;
    final direction = (end - start) / distance;
    var drawn = 0.0;
    while (drawn < distance) {
      final next = (drawn + dash).clamp(0.0, distance);
      canvas.drawLine(
        start + direction * drawn,
        start + direction * next,
        paint,
      );
      drawn += dash + gap;
    }
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect, Paint paint) {
    final bracketPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.square
      ..color = paint.color;
    final len = rect.width * .18;
    for (final corner in [
      (
        Offset(rect.left, rect.top),
        Offset(rect.left + len, rect.top),
        Offset(rect.left, rect.top + len),
      ),
      (
        Offset(rect.right, rect.top),
        Offset(rect.right - len, rect.top),
        Offset(rect.right, rect.top + len),
      ),
      (
        Offset(rect.left, rect.bottom),
        Offset(rect.left + len, rect.bottom),
        Offset(rect.left, rect.bottom - len),
      ),
      (
        Offset(rect.right, rect.bottom),
        Offset(rect.right - len, rect.bottom),
        Offset(rect.right, rect.bottom - len),
      ),
    ]) {
      canvas.drawLine(corner.$1, corner.$2, bracketPaint);
      canvas.drawLine(corner.$1, corner.$3, bracketPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FaceGuidePainter oldDelegate) =>
      oldDelegate.scanning != scanning;
}
