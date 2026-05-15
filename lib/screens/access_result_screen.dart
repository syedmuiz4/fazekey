import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/access_log.dart';
import '../models/app_user.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/primary_button.dart';
import 'dashboard_screen.dart';
import 'face_login_screen.dart';

class AccessResultScreen extends StatelessWidget {
  const AccessResultScreen({super.key});
  static const route = '/access-result';

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ??
        {};
    final user = args['user'] as AppUser?;
    final log = args['log'] as AccessLog?;
    final granted = user != null;
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: .6, end: 1),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.elasticOut,
                  builder: (_, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: CircleAvatar(
                    radius: 62,
                    backgroundColor: granted
                        ? const Color(0xFF00E5A8)
                        : Theme.of(context).colorScheme.error,
                    child: Icon(
                      granted ? Icons.check_rounded : Icons.close_rounded,
                      color: Colors.white,
                      size: 72,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  granted ? 'Access Granted' : 'Access Denied',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                GlassCard(
                  child: Column(
                    children: [
                      Text(
                        user?.name ?? log?.userName ?? 'Unknown face',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        granted
                            ? '${user.department} - Room ${user.room}'
                            : (log?.reason ?? 'Face not recognized'),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                PrimaryButton(
                  label: 'Back to Dashboard',
                  icon: Icons.dashboard_rounded,
                  onPressed: () =>
                      _replaceAfterFrame(context, DashboardScreen.route),
                ),
                TextButton(
                  onPressed: () =>
                      _replaceAfterFrame(context, FaceLoginScreen.route),
                  child: const Text('Scan another face'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _replaceAfterFrame(BuildContext context, String route) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      Navigator.pushReplacementNamed(context, route);
    });
  }
}
