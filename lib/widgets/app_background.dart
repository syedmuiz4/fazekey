import 'package:flutter/material.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [
            Color(0xFFF0F9FF),
            Color(0xFFE0F2FE),
            Color(0xFFE6FFFB),
          ],
        ),
      ),
      child: child,
    );
  }
}
