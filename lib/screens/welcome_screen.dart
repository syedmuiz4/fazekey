import 'package:flutter/material.dart';

import '../widgets/app_background.dart';
import '../widgets/primary_button.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  static const route = '/welcome';
  static const _logoHeroTag = 'facekey-logo';

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
                Hero(
                  tag: _logoHeroTag,
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 220.0,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'FaceKey',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                Text(
                  'A smart campus access control console for secure face-first entry.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                PrimaryButton(
                  label: 'Get Started',
                  onPressed: () => Navigator.pushNamed(context, LoginScreen.route),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
