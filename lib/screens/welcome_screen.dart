import 'package:flutter/material.dart';

import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                const Icon(Icons.verified_user_rounded, size: 72),
                const SizedBox(height: 20),
                Text('FaceKey', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Text(
                  'A smart campus access control console for secure face-first entry.',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                GlassCard(
                  child: Column(
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.offline_bolt_rounded),
                          SizedBox(width: 12),
                          Expanded(child: Text('Offline MobileFaceNet matching with Firestore sync')),
                        ],
                      ),
                      const SizedBox(height: 18),
                      PrimaryButton(
                        label: 'Get Started',
                        icon: Icons.arrow_forward_rounded,
                        onPressed: () => Navigator.pushNamed(context, LoginScreen.route),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
