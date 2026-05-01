import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

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

class _SplashScreenState extends State<SplashScreen> {
  static const _logoHeroTag = 'facekey-logo';

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      Navigator.pushReplacementNamed(context, auth.isAuthenticated ? DashboardScreen.route : WelcomeScreen.route);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
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
                    child: Shimmer.fromColors(
                      baseColor: Colors.white,
                      highlightColor: Theme.of(context).colorScheme.primary.withValues(alpha: .46),
                      period: const Duration(milliseconds: 2100),
                      child: Image.asset(
                        'assets/images/logo1.png',
                        width: 320.0,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 24,
                child: Text(
                  'v1.0.0',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
