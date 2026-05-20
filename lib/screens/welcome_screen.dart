import 'package:flutter/material.dart';

import '../widgets/app_background.dart';
import '../widgets/corporate_chrome.dart';
import '../widgets/primary_button.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  static const route = '/welcome';
  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(),
                Image.asset(
                  'assets/images/logo2.png',
                  width: 220,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
                const SizedBox(height: 18),
                Text(
                  'Campus Access',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: CorporateColors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'A smart campus access control console for secure entry.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: CorporateColors.mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                PrimaryButton(
                  label: 'Get Started',
                  onPressed: () =>
                      Navigator.pushNamed(context, LoginScreen.route),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
