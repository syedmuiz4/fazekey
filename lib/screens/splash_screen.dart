import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../widgets/app_background.dart';
import 'dashboard_screen.dart';
import 'welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  static const route = '/';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _logoHeroTag = 'facekey-logo';
  final Key _scaffoldKey = UniqueKey();
  late final AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      Navigator.of(context).pushNamedAndRemoveUntil(
        auth.isAuthenticated ? DashboardScreen.route : WelcomeScreen.route,
        (_) => false,
      );
    });
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        body: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 1250),
                curve: Curves.easeOutExpo,
                builder: (_, value, child) => Opacity(
                  opacity: value.clamp(0, 1),
                  child: Transform.scale(
                    scale: .82 + (.18 * value),
                    child: child,
                  ),
                ),
                child: Hero(
                  tag: _logoHeroTag,
                  child: _FaceIdentityLogoScan(controller: _scanController),
                ),
              ),
            ),
            Positioned(
              bottom: 24,
              child: SafeArea(
                child: Text(
                  'v1.0.0',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaceIdentityLogoScan extends StatelessWidget {
  const _FaceIdentityLogoScan({required this.controller});

  final Animation<double> controller;

  @override
  Widget build(BuildContext context) {
    const logoWidth = 320.0;
    const logoHeight = 400.0;
    return SizedBox(
      width: logoWidth,
      height: logoHeight,
      child: ClipRect(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.asset(
              'assets/images/logo2.png',
              width: logoWidth,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
            Positioned(
              bottom: 18,
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final glow =
                      .55 +
                      (.45 * Curves.easeInOut.transform(controller.value));
                  return Column(
                    children: [
                      Text(
                        'Face Identity Scan',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: const Color(
                            0xFF22D3EE,
                          ).withValues(alpha: glow),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 132,
                        height: 2,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF22D3EE,
                          ).withValues(alpha: glow),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF22D3EE,
                              ).withValues(alpha: glow),
                              blurRadius: 16,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final top =
                    (logoHeight + 40) *
                        Curves.easeInOutCubic.transform(controller.value) -
                    20;
                return Positioned(
                  top: top,
                  left: 10,
                  right: 10,
                  child: IgnorePointer(
                    child: Column(
                      children: [
                        Container(
                          height: 2.5,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22D3EE),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF22D3EE,
                                ).withValues(alpha: .92),
                                blurRadius: 18,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 26,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color(0xFF22D3EE).withValues(alpha: .24),
                                const Color(0xFF22D3EE).withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
