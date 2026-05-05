import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
                    'assets/images/logo2.png',
                    width: 220.0,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                const SizedBox(height: 18),
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF22D3EE), Color(0xFFA855F7)],
                  ).createShader(bounds),
                  child: Text(
                    'FaceKey',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.montserrat(
                      textStyle: Theme.of(context).textTheme.displayLarge,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'A smart campus access control console for secure face-first entry.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    textStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: .7),
                    ),
                    fontWeight: FontWeight.w500,
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
