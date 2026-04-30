import 'package:flutter/material.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF080A12), Color(0xFF17122E), Color(0xFF061B22)]
              : const [Color(0xFFF7FAFF), Color(0xFFEDEBFF), Color(0xFFE6FFF6)],
        ),
      ),
      child: child,
    );
  }
}
