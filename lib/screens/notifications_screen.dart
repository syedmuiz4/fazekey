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
  bool _adminReadScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        unawaited(
          context.read<AlertProvider>().markAllRead().catchError((_) {}),
        );
      });
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
          backgroundColor: AppBackground.slateGray,
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: context.read<FirebaseService>().watchAdminNotifications(),
          builder: (context, adminSnapshot) {
            final firebase = context.read<FirebaseService>();
            final adminNotifications = adminSnapshot.data?.docs ?? const [];
            if (!_adminReadScheduled &&
                adminNotifications.any((doc) => doc.data()['read'] != true)) {
              _adminReadScheduled = true;
              Future<void>.delayed(const Duration(milliseconds: 700), () {
                if (!mounted) return;
                unawaited(
                  firebase.markAdminNotificationsRead().catchError((_) {}),
                );
              });
            }
            return StreamBuilder<List<RoomAccessRequest>>(
              stream: firebase.watchRoomAccessRequests(),
              builder: (context, snapshot) {
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
                                    adminNotifications.isEmpty &&
                                    requests.isEmpty &&
                                    resetRequests.isEmpty &&
                                    supportRequests.isEmpty &&
                                    profileRequests.isEmpty &&
                                    photoRequests.isEmpty) {
                                  return const _EmptyAlerts();
                                }
                                final notificationItems =
                                    <_DatedNotificationItem>[
                                      for (final notification
                                          in adminNotifications)
                                        _DatedNotificationItem(
                                          timestamp: _documentCreatedAt(
                                            notification,
                                          ),
                                          priority: _adminNotificationPriority(
                                            notification,
                                          ),
                                          child: _AdminNotificationCard(
                                            doc: notification,
                                          ),
                                        ),
                                      for (final request in photoRequests)
                                        _DatedNotificationItem(
                                          timestamp: _documentCreatedAt(
                                            request,
                                          ),
                                          priority: 1,
                                          child: _ProfilePhotoRequestCard(
                                            doc: request,
                                          ),
                                        ),
                                      for (final request in profileRequests)
                                        _DatedNotificationItem(
                                          timestamp: _documentCreatedAt(
                                            request,
                                          ),
                                          priority: 1,
                                          child: _ProfileChangeRequestCard(
                                            doc: request,
                                          ),
                                        ),
                                      for (final request in supportRequests)
                                        _DatedNotificationItem(
                                          timestamp: _documentCreatedAt(
                                            request,
                                          ),
                                          priority: 1,
                                          child: _SupportRequestCard(
                                            doc: request,
                                          ),
                                        ),
                                      for (final request in resetRequests)
                                        _DatedNotificationItem(
                                          timestamp: _documentCreatedAt(
                                            request,
                                          ),
                                          priority: 1,
                                          child: _PasswordResetRequestCard(
                                            doc: request,
                                          ),
                                        ),
                                      for (final request in requests)
                                        _DatedNotificationItem(
                                          timestamp: request.createdAt,
                                          priority: 0,
                                          child: _RoomRequestCard(
                                            request: request,
                                          ),
                                        ),
                                      for (final alert in alerts)
                                        _DatedNotificationItem(
                                          timestamp: alert.timestamp,
                                          priority: alert.read ? 4 : 2,
                                          child: _AlertCard(alert: alert),
                                        ),
                                    ]..sort((a, b) {
                                      final priority = a.priority.compareTo(
                                        b.priority,
                                      );
                                      if (priority != 0) return priority;
                                      return b.timestamp.compareTo(a.timestamp);
                                    });
                                return ListView(
                                  padding: const EdgeInsets.all(18),
                                  children: [
                                    for (final item in notificationItems) ...[
                                      item.child,
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
            );
          },
        ),
      ),
    );
  }
}

DateTime _documentCreatedAt(
  QueryDocumentSnapshot<Map<String, dynamic>> document,
) {
  return (document.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
}

class _DatedNotificationItem {
  const _DatedNotificationItem({
    required this.timestamp,
    required this.child,
    this.priority = 3,
  });

  final DateTime timestamp;
  final Widget child;
  final int priority;
}

int _adminNotificationPriority(
  QueryDocumentSnapshot<Map<String, dynamic>> notification,
) {
  final data = notification.data();
  final unread = data['read'] != true;
  final type = (data['type'] ?? '').toString();
  if (unread && type == 'first_login') return 0;
  if (unread) return 2;
  return 4;
}

class _HighlightedRequestCard extends StatelessWidget {
  const _HighlightedRequestCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22D3EE).withValues(alpha: .3),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _AdminNotificationCard extends StatelessWidget {
  const _AdminNotificationCard({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final title = (data['title'] ?? 'Notification').toString();
    final message = (data['message'] ?? '').toString();
    final type = (data['type'] ?? 'notification').toString();
    final unread = data['read'] != true;
    final timestamp =
        (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: unread
            ? [
                BoxShadow(
                  color: const Color(0xFF22D3EE).withValues(alpha: .35),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : const [],
      ),
      child: GlassCard(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: unread
                ? const Color(0xFF22D3EE).withValues(alpha: .18)
                : const Color(0xFF64748B).withValues(alpha: .12),
            child: Icon(
              unread
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_rounded,
              color: unread ? const Color(0xFF0891B2) : const Color(0xFF64748B),
            ),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: unread ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
          subtitle: Text(
            '$message\n${DateFormat.yMMMd().add_jm().format(timestamp)}',
          ),
          trailing: Text(
            unread ? 'NEW' : type.toUpperCase(),
            style: TextStyle(
              color: unread ? const Color(0xFF0891B2) : const Color(0xFF64748B),
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
          isThreeLine: true,
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
    return _HighlightedRequestCard(
      child: GlassCard(
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
    return _HighlightedRequestCard(
      child: GlassCard(
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
    return _HighlightedRequestCard(
      child: GlassCard(
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
    return _HighlightedRequestCard(
      child: GlassCard(
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
    return _HighlightedRequestCard(
      child: GlassCard(
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
              '${_roomRequestStatus(request)}\n'
              '${DateFormat.yMMMd().add_jm().format(request.createdAt)}',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _decide(context, firebase, true),
                    child: const Text('Allow'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _decide(context, firebase, false),
                    child: const Text('Deny'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _decide(
    BuildContext context,
    FirebaseService firebase,
    bool allowed,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await firebase.decideRoomAccessRequest(
        request: request,
        allowed: allowed,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            allowed
                ? '${request.userName} is now checked in to ${request.areaName}.'
                : 'Room request denied.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

String _roomRequestStatus(RoomAccessRequest request) {
  final previous = request.previousRoomName.trim();
  if (request.exitedPreviousRoom) {
    return 'Room status: User already exited ${previous.isEmpty ? 'the previous room' : previous}.';
  }
  if (previous.isNotEmpty) {
    return 'Room status: User has not exited $previous yet.';
  }
  return 'Room status: No active room session found before request.';
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final SecurityAlert alert;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(alert.severity);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: alert.read
            ? const []
            : [
                BoxShadow(
                  color: color.withValues(alpha: .3),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
      ),
      child: GlassCard(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: alert.read ? .12 : .2),
            child: Icon(_severityIcon(alert.severity), color: color),
          ),
          title: Text(
            alert.title,
            style: TextStyle(
              fontWeight: alert.read ? FontWeight.w800 : FontWeight.w900,
            ),
          ),
          subtitle: Text(
            '${alert.body}\n${DateFormat.yMMMd().add_jm().format(alert.timestamp)}',
          ),
          trailing: Chip(
            visualDensity: VisualDensity.compact,
            label: Text(alert.read ? alert.severity : 'NEW'),
            side: BorderSide(color: color.withValues(alpha: .32)),
            backgroundColor: color.withValues(alpha: alert.read ? .10 : .16),
          ),
          isThreeLine: true,
        ),
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
