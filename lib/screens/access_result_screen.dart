import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../models/access_log.dart';
import '../models/app_user.dart';
import '../services/firebase_service.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/primary_button.dart';
import 'dashboard_screen.dart';
import 'face_login_screen.dart';
import 'user_dashboard_screen.dart';

class AccessResultScreen extends StatefulWidget {
  const AccessResultScreen({super.key});
  static const route = '/access-result';

  @override
  State<AccessResultScreen> createState() => _AccessResultScreenState();
}

class _AccessResultScreenState extends State<AccessResultScreen> {
  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ??
        {};
    final user = args['user'] as AppUser?;
    final log = args['log'] as AccessLog?;
    final waitingApproval = args['waitingApproval'] == true;
    final requestedRoom = (args['requestedRoom'] ?? '').toString();
    final granted = !waitingApproval && (log?.granted == true || user != null);
    final locked = log?.status == 'locked';
    final accent = waitingApproval
        ? const Color(0xFFF59E0B)
        : granted
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);
    final dashboardRoute =
        args['dashboardRoute'] as String? ??
        (user?.isAdmin == true
            ? DashboardScreen.route
            : UserDashboardScreen.route);
    final backRoute = args['backRoute'] as String? ?? FaceLoginScreen.route;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _replaceAfterFrame(context, backRoute);
        }
      },
      child: AppBackground(
        child: Scaffold(
          backgroundColor: accent.withValues(alpha: .92),
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
                      backgroundColor: Colors.white,
                      child: Icon(
                        granted
                            ? Icons.verified_user_rounded
                            : waitingApproval
                            ? Icons.hourglass_top_rounded
                            : Icons.cancel_rounded,
                        color: accent,
                        size: 72,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    granted
                        ? 'Verified'
                        : waitingApproval
                        ? 'Waiting for Approval'
                        : locked
                        ? 'Locked'
                        : 'Denied',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 18),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (waitingApproval)
                          _WaitingDetails(user: user, room: requestedRoom)
                        else if (granted && user != null)
                          _VerifiedDetails(user: user, log: log)
                        else
                          _DeniedDetails(
                            reason: log?.reason ?? 'Face not recognized',
                          ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  PrimaryButton(
                    label: granted
                        ? 'Dashboard'
                        : waitingApproval
                        ? 'Back to Login'
                        : 'Scan Face Again',
                    icon: granted
                        ? Icons.dashboard_rounded
                        : waitingApproval
                        ? Icons.login_rounded
                        : Icons.face_retouching_natural_rounded,
                    onPressed: () => _replaceAfterFrame(
                      context,
                      granted ? dashboardRoute : backRoute,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _replaceAfterFrame(
                      context,
                      granted || waitingApproval ? backRoute : dashboardRoute,
                    ),
                    child: Text(
                      granted || waitingApproval
                          ? 'Back'
                          : 'Request Administrator Assistance',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _replaceAfterFrame(BuildContext context, String route) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(route, (_) => false);
    });
  }
}

class _WaitingDetails extends StatelessWidget {
  const _WaitingDetails({required this.user, required this.room});

  final AppUser? user;
  final String room;

  @override
  Widget build(BuildContext context) {
    final displayName = user?.name.trim().isNotEmpty == true
        ? user!.name.trim()
        : 'Verified user';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(
            displayName,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 12),
        _ResultLine(label: 'Status', value: 'Waiting for admin approval'),
        _ResultLine(label: 'Requested Room', value: _valueOrUnavailable(room)),
        const SizedBox(height: 12),
        const Text(
          'Your face was verified. Admin must approve this first room entry before the dashboard opens.',
          style: TextStyle(
            color: Color(0xFF475569),
            fontWeight: FontWeight.w700,
          ),
        ),
        if (user != null) ...[
          const SizedBox(height: 12),
          StreamBuilder(
            stream: context.read<FirebaseService>().watchActiveRoomSession(
              user!.id,
            ),
            builder: (context, snapshot) {
              if (snapshot.data != null) {
                SchedulerBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    UserDashboardScreen.route,
                    (_) => false,
                  );
                });
                return const Text(
                  'Approved. Opening your dashboard...',
                  style: TextStyle(fontWeight: FontWeight.w900),
                );
              }
              return const Text(
                'Waiting for admin approval...',
                style: TextStyle(fontWeight: FontWeight.w900),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _VerifiedDetails extends StatelessWidget {
  const _VerifiedDetails({required this.user, required this.log});

  final AppUser user;
  final AccessLog? log;

  @override
  Widget build(BuildContext context) {
    final logArea = log?.areaName.trim() ?? '';
    final isApplicationLogin =
        logArea.toLowerCase().replaceAll(RegExp(r'\s+'), '') ==
        'applicationfacelogin';
    final room = logArea.isNotEmpty && !isApplicationLogin
        ? logArea
        : user.assignedRoomsLabel;
    final academicValue = user.position.trim().toLowerCase() == 'staff'
        ? user.department
        : user.course;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(
            user.name.trim().isEmpty ? 'Verified user' : user.name.trim(),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 14),
        _ResultLine(label: 'Status', value: 'Face verified'),
        _ResultLine(
          label: 'ID',
          value: _valueOrUnavailable(user.identityNumber),
        ),
        _ResultLine(label: 'Category', value: user.roleLabel),
        _ResultLine(
          label: isApplicationLogin ? 'Access Status' : 'Room Status',
          value: isApplicationLogin
              ? 'Application login verified'
              : user.isAdmin
              ? 'Available'
              : _valueOrUnavailable(room),
        ),
        _ResultLine(
          label: user.position.trim().toLowerCase() == 'staff'
              ? 'Department'
              : 'Programme',
          value: _valueOrUnavailable(academicValue),
        ),
      ],
    );
  }
}

class _DeniedDetails extends StatelessWidget {
  const _DeniedDetails({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(
            'Verification unsuccessful',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 12),
        Text(reason, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        const Text(
          'Please scan your face again in a well-lit area and keep your face centered. If the issue continues, please request assistance from the administrator.',
          style: TextStyle(
            color: Color(0xFF475569),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

String _valueOrUnavailable(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'Unavailable' : trimmed;
}
