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
      if (mounted) context.read<AlertProvider>().markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<AlertProvider>().alerts;
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
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
                    if (alerts.isEmpty &&
                        requests.isEmpty &&
                        resetRequests.isEmpty &&
                        supportRequests.isEmpty) {
                      return const _EmptyAlerts();
                    }
                    return ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
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

class _PasswordResetRequestCard extends StatelessWidget {
  const _PasswordResetRequestCard({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final firebase = context.read<FirebaseService>();
    final data = doc.data();
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
          FilledButton(
            onPressed: () => firebase.firestore
                .collection('passwordResetRequests')
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
                  child: const Text('Revoke'),
                ),
              ),
            ],
          ),
        ],
      ),
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
