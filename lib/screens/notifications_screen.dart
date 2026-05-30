import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/room_access_request.dart';
import '../models/security_alert.dart';
import '../providers/alert_provider.dart';
import '../services/firebase_service.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  static const route = '/notifications';

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<AlertProvider>().markAllRead().catchError((_) {}));
      unawaited(
        context.read<FirebaseService>().markAdminNotificationsRead().catchError(
          (_) {},
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<AlertProvider>().alerts;
    return AppBackground(
      child: Scaffold(
        backgroundColor: AppBackground.slateGray,
        appBar: AppBar(
          title: const Text('Recent Alerts'),
          backgroundColor: Colors.transparent,
        ),
        body: StreamBuilder<List<RoomAccessRequest>>(
          stream: context.read<FirebaseService>().watchRoomAccessRequests(),
          builder: (context, snapshot) {
            final firebase = context.read<FirebaseService>();
            final requests = (snapshot.data ?? const <RoomAccessRequest>[])
                .where((request) => request.isOpen)
                .toList();
            return StreamBuilder(
              stream: firebase.firestore
                  .collection('passwordResetRequests')
                  .where('status', isEqualTo: 'open')
                  .snapshots(),
              builder: (context, resetSnapshot) {
                final resetRequests = resetSnapshot.data?.docs ?? const [];
                return StreamBuilder(
                  stream: firebase.firestore
                      .collection('supportRequests')
                      .where('status', isEqualTo: 'open')
                      .snapshots(),
                  builder: (context, supportSnapshot) {
                    final supportRequests =
                        supportSnapshot.data?.docs ?? const [];
                    return StreamBuilder(
                      stream: firebase.firestore
                          .collection('profileChangeRequests')
                          .where('status', isEqualTo: 'open')
                          .snapshots(),
                      builder: (context, profileSnapshot) {
                        final profileRequests =
                            profileSnapshot.data?.docs ?? const [];
                        return StreamBuilder(
                          stream: firebase.firestore
                              .collection('profilePhotoRequests')
                              .where('status', isEqualTo: 'open')
                              .snapshots(),
                          builder: (context, photoSnapshot) {
                            final photoRequests =
                                photoSnapshot.data?.docs ?? const [];
                            if (alerts.isEmpty &&
                                requests.isEmpty &&
                                resetRequests.isEmpty &&
                                supportRequests.isEmpty &&
                                profileRequests.isEmpty &&
                                photoRequests.isEmpty) {
                              return const _EmptyAlerts();
                            }
                            return ListView(
                              padding: const EdgeInsets.all(18),
                              children: [
                                for (final request in photoRequests) ...[
                                  _ProfilePhotoRequestCard(doc: request),
                                  const SizedBox(height: 12),
                                ],
                                for (final request in profileRequests) ...[
                                  _ProfileChangeRequestCard(doc: request),
                                  const SizedBox(height: 12),
                                ],
                                for (final request in supportRequests) ...[
                                  _SupportRequestCard(doc: request),
                                  const SizedBox(height: 12),
                                ],
                                for (final request in resetRequests) ...[
                                  _PasswordResetRequestCard(doc: request),
                                  const SizedBox(height: 12),
                                ],
                                for (final request in requests) ...[
                                  _RoomRequestCard(request: request),
                                  const SizedBox(height: 12),
                                ],
                                for (final alert in alerts) ...[
                                  _AlertCard(alert: alert),
                                  const SizedBox(height: 12),
                                ],
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SupportRequestCard extends StatelessWidget {
  const _SupportRequestCard({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final firebase = context.read<FirebaseService>();
    final data = doc.data();
    final userName = (data['userName'] ?? 'User').toString();
    final email = (data['email'] ?? '').toString();
    final contact = (data['contact'] ?? '').toString();
    final subject = (data['subject'] ?? 'Support request').toString();
    final message = (data['message'] ?? '').toString();
    final timestamp =
        (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Help & Support Request',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            '$userName\n'
            '$email\n'
            'Contact: $contact\n'
            '${DateFormat.yMMMd().add_jm().format(timestamp)}',
          ),
          const SizedBox(height: 8),
          Text(subject, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(message),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => firebase.firestore
                .collection('supportRequests')
                .doc(doc.id)
                .set({
                  'status': 'handled',
                  'handledAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true)),
            child: const Text('Mark Handled'),
          ),
        ],
      ),
    );
  }
}

class _ProfilePhotoRequestCard extends StatelessWidget {
  const _ProfilePhotoRequestCard({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final firebase = context.read<FirebaseService>();
    final data = doc.data();
    final userId = (data['userId'] ?? '').toString();
    final userName = (data['userName'] ?? 'User').toString();
    final email = (data['email'] ?? '').toString();
    final photoUrl = (data['photoUrl'] ?? '').toString();
    final timestamp =
        (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final file = photoUrl.trim().isEmpty ? null : File(photoUrl);
    final image = file != null && file.existsSync() ? FileImage(file) : null;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profile Picture Request',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundImage: image,
                child: image == null
                    ? const Icon(Icons.person_rounded, size: 30)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$userName requested a new profile picture.\n'
                  '$email\n'
                  '${DateFormat.yMMMd().add_jm().format(timestamp)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DecisionButtons(
            approveLabel: 'Approve',
            denyLabel: 'Deny',
            onApprove: () => firebase.decideProfilePhotoRequest(
              requestId: doc.id,
              userId: userId,
              approved: true,
            ),
            onDeny: () => firebase.decideProfilePhotoRequest(
              requestId: doc.id,
              userId: userId,
              approved: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileChangeRequestCard extends StatelessWidget {
  const _ProfileChangeRequestCard({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final firebase = context.read<FirebaseService>();
    final data = doc.data();
    final userId = (data['userId'] ?? '').toString();
    final userName = (data['userName'] ?? 'User').toString();
    final email = (data['email'] ?? '').toString();
    final requested = Map<String, dynamic>.from(
      data['requested'] as Map? ?? const {},
    );
    final timestamp =
        (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profile Change Request',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            '$userName\n'
            '$email\n'
            '${DateFormat.yMMMd().add_jm().format(timestamp)}',
          ),
          const SizedBox(height: 10),
          _RequestDetail(label: 'Name', value: requested['name']),
          _RequestDetail(label: 'Department', value: requested['department']),
          _RequestDetail(label: 'Phone', value: requested['phone']),
          _RequestDetail(
            label: 'Home Address',
            value: requested['homeAddress'],
          ),
          _RequestDetail(
            label: 'Emergency Contact',
            value: requested['emergencyContact'],
          ),
          const SizedBox(height: 12),
          _DecisionButtons(
            approveLabel: 'Approve',
            denyLabel: 'Deny',
            onApprove: () => firebase.decideProfileChangeRequest(
              requestId: doc.id,
              userId: userId,
              approved: true,
              requested: requested,
            ),
            onDeny: () => firebase.decideProfileChangeRequest(
              requestId: doc.id,
              userId: userId,
              approved: false,
              requested: requested,
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordResetRequestCard extends StatelessWidget {
  const _PasswordResetRequestCard({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final firebase = context.read<FirebaseService>();
    final data = doc.data();
    final userId = (data['userId'] ?? '').toString();
    final userName = (data['userName'] ?? 'User').toString();
    final email = (data['email'] ?? '').toString();
    final timestamp =
        (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Password Reset Request',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            '$userName requested a temporary password.\n'
            '$email\n'
            '${DateFormat.yMMMd().add_jm().format(timestamp)}',
          ),
          const SizedBox(height: 12),
          _DecisionButtons(
            approveLabel: 'Approve',
            denyLabel: 'Deny',
            onApprove: () => firebase.decidePasswordResetRequest(
              requestId: doc.id,
              userId: userId,
              approved: true,
            ),
            onDeny: () => firebase.decidePasswordResetRequest(
              requestId: doc.id,
              userId: userId,
              approved: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomRequestCard extends StatelessWidget {
  const _RoomRequestCard({required this.request});

  final RoomAccessRequest request;

  @override
  Widget build(BuildContext context) {
    final firebase = context.read<FirebaseService>();
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Room Access Request',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            '${request.userName} wants to enter ${request.areaName}.\n'
            '${DateFormat.yMMMd().add_jm().format(request.createdAt)}',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => firebase.decideRoomAccessRequest(
                    request: request,
                    allowed: true,
                  ),
                  child: const Text('Allow'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => firebase.decideRoomAccessRequest(
                    request: request,
                    allowed: false,
                  ),
                  child: const Text('Deny'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RequestDetail extends StatelessWidget {
  const _RequestDetail({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('$label: $text'),
    );
  }
}

class _DecisionButtons extends StatelessWidget {
  const _DecisionButtons({
    required this.approveLabel,
    required this.denyLabel,
    required this.onApprove,
    required this.onDeny,
  });

  final String approveLabel;
  final String denyLabel;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton(onPressed: onApprove, child: Text(approveLabel)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton(onPressed: onDeny, child: Text(denyLabel)),
        ),
      ],
    );
  }
}

class _EmptyAlerts extends StatelessWidget {
  const _EmptyAlerts();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No alerts recorded',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'Intrusion, lockdown, and denied-access events will appear here when they occur.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final SecurityAlert alert;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(alert.severity);
    return GlassCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .16),
          child: Icon(_severityIcon(alert.severity), color: color),
        ),
        title: Text(
          alert.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${alert.body}\n${DateFormat.yMMMd().add_jm().format(alert.timestamp)}',
        ),
        trailing: Chip(
          visualDensity: VisualDensity.compact,
          label: Text(alert.severity),
          side: BorderSide(color: color.withValues(alpha: .32)),
          backgroundColor: color.withValues(alpha: .10),
        ),
        isThreeLine: true,
      ),
    );
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return const Color(0xFFE11D48);
      case 'high':
        return const Color(0xFFFF5B66);
      case 'medium':
        return const Color(0xFFFDB022);
      default:
        return const Color(0xFF22D3EE);
    }
  }

  IconData _severityIcon(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Icons.emergency_rounded;
      case 'high':
        return Icons.warning_rounded;
      case 'medium':
        return Icons.shield_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }
}
