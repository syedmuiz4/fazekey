import 'package:flutter/material.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.loading = false, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final labelText = Text(label, style: const TextStyle(fontWeight: FontWeight.w800));
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: loading || icon != null
          ? FilledButton.icon(
              onPressed: loading ? null : onPressed,
              icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon),
              label: labelText,
            )
          : FilledButton(
              onPressed: onPressed,
              child: labelText,
            ),
    );
  }
}
