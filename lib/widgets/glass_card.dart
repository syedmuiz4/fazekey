import 'package:flutter/material.dart';

import 'corporate_chrome.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : Colors.white.withValues(alpha: .96);
    final border = dark
        ? Theme.of(context).colorScheme.outlineVariant
        : const Color(0xFF99F6E4).withValues(alpha: .88);
    final shadow = dark
        ? Colors.black.withValues(alpha: .18)
        : CorporateColors.lightBlue.withValues(alpha: .22);
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: shadow,
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              const SizedBox(height: 14),
              const DashedDivider(),
            ],
          ),
        ),
      ),
    );
  }
}
