import 'package:flutter/material.dart';

class CorporateColors {
  const CorporateColors._();

  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceHigh = Color(0xFFF8FDFF);
  static const border = Color(0xFFD8E7EC);
  static const mutedBorder = Color(0xFFEAF3F6);
  static const teal = Color(0xFF0D9488);
  static const lightBlue = Color(0xFFBAE6FD);
  static const text = Color(0xFF0F172A);
  static const mutedText = Color(0xFF64748B);
}

class BiometricBrandMark extends StatelessWidget {
  const BiometricBrandMark({super.key, this.size = 104});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _BiometricBrandPainter()),
    );
  }
}

class FloatingSystemNav extends StatelessWidget {
  const FloatingSystemNav({super.key, this.activeIndex = 0});

  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    const icons = [
      Icons.home_rounded,
      Icons.receipt_long_rounded,
      Icons.vpn_key_rounded,
      Icons.settings_rounded,
    ];
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: CorporateColors.mutedBorder)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              width: 236,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .96),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: CorporateColors.border),
                boxShadow: [
                  BoxShadow(
                    color: CorporateColors.teal.withValues(alpha: .14),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < icons.length; i++)
                    SizedBox.square(
                      dimension: 42,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            icons[i],
                            color: i == activeIndex
                                ? CorporateColors.teal
                                : CorporateColors.mutedText,
                            size: 22,
                          ),
                          if (i == activeIndex)
                            Positioned(
                              bottom: 4,
                              child: Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: CorporateColors.teal,
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: [
                                    BoxShadow(
                                      color: CorporateColors.teal.withValues(
                                        alpha: .65,
                                      ),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashedDivider extends StatelessWidget {
  const DashedDivider({super.key, this.height = 1});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _DashedLinePainter()),
    );
  }
}

class MatrixTextBlock extends StatelessWidget {
  const MatrixTextBlock({
    super.key,
    required this.lines,
    this.style,
    this.spacing = 6,
  });

  final List<String> lines;
  final TextStyle? style;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final baseStyle =
        style ??
        Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: CorporateColors.text,
          fontWeight: FontWeight.w700,
          height: 1.35,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          Text(lines[i], style: baseStyle),
          if (i != lines.length - 1) SizedBox(height: spacing),
        ],
      ],
    );
  }
}

class _BiometricBrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final teal = CorporateColors.teal;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = teal.withValues(alpha: .78);
    final faintPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = CorporateColors.mutedText.withValues(alpha: .34);
    for (final radius in [
      size.width * .15,
      size.width * .25,
      size.width * .35,
    ]) {
      canvas.drawCircle(center, radius, ringPaint);
    }
    canvas.drawCircle(center, size.width * .06, Paint()..color = teal);
    canvas.drawLine(
      Offset(center.dx - size.width * .42, center.dy),
      Offset(center.dx - size.width * .28, center.dy),
      faintPaint,
    );
    canvas.drawLine(
      Offset(center.dx + size.width * .28, center.dy),
      Offset(center.dx + size.width * .42, center.dy),
      faintPaint,
    );
    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square
      ..color = teal;
    final inset = size.width * .08;
    final len = size.width * .18;
    final left = inset;
    final right = size.width - inset;
    final top = inset;
    final bottom = size.height - inset;
    for (final corner in [
      (Offset(left, top), Offset(left + len, top), Offset(left, top + len)),
      (Offset(right, top), Offset(right - len, top), Offset(right, top + len)),
      (
        Offset(left, bottom),
        Offset(left + len, bottom),
        Offset(left, bottom - len),
      ),
      (
        Offset(right, bottom),
        Offset(right - len, bottom),
        Offset(right, bottom - len),
      ),
    ]) {
      canvas.drawLine(corner.$1, corner.$2, bracket);
      canvas.drawLine(corner.$1, corner.$3, bracket);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = CorporateColors.border
      ..strokeWidth = size.height.clamp(1, 2);
    const dash = 4.0;
    const gap = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, 0),
        Offset((x + dash).clamp(0, size.width), 0),
        paint,
      );
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
