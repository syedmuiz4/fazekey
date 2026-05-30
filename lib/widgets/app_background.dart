import 'package:flutter/material.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  static const slateGray = Color(0xFF334155);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: slateGray, child: child);
  }
}
