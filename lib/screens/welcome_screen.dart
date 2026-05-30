import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/app_background.dart';
import '../widgets/primary_button.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  static const route = '/welcome';
  @override
  Widget build(BuildContext context) {
    final logoHeight = (MediaQuery.sizeOf(context).height * .30)
        .clamp(220.0, 320.0)
        .toDouble();
    return AppBackground(
      child: Scaffold(
        backgroundColor: AppBackground.slateGray,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'FAZEKEY',
                    style:
                        GoogleFonts.orbitron(
                          fontSize: 120,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -5,
                          height: .85,
                        ).copyWith(
                          color: const Color(0xFF00E5FF),
                          shadows: [
                            Shadow(
                              color: const Color(
                                0xFF00E5FF,
                              ).withValues(alpha: .72),
                              blurRadius: 25,
                            ),
                          ],
                        ),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Image.asset(
                        'assets/images/logo3_.png',
                        height: logoHeight,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Secure identity verification and room access management for FSKTM facilities.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
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
