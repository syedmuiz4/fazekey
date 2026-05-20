import 'package:flutter/material.dart';

import 'corporate_chrome.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: CorporateColors.background, child: child);
  }
}
