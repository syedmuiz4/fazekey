import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  static const route = '/notifications';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final alerts = [
      _DemoAlert(
        title: 'Door access normalized',
        body: 'Level 1 - Access Lab returned to normal access flow.',
        severity: 'Info',
        timestamp: now.subtract(const Duration(minutes: 4)),
        icon: Icons.check_circle_rounded,
        color: const Color(0xFF32D583),
      ),
      _DemoAlert(
        title: 'Unknown face attempt',
        body: 'Unrecognized scan was denied at Level 2 - Research Suite.',
        severity: 'High',
        timestamp: now.subtract(const Duration(minutes: 18)),
        icon: Icons.face_retouching_off_rounded,
        color: const Color(0xFFFF5B66),
      ),
      _DemoAlert(
        title: 'Incident report received',
        body: 'Security desk logged a medium-priority corridor inspection.',
        severity: 'Medium',
        timestamp: now.subtract(const Duration(hours: 1, minutes: 6)),
        icon: Icons.assignment_rounded,
        color: const Color(0xFFFDB022),
      ),
      _DemoAlert(
        title: 'Cloud sync complete',
        body: 'All access logs and profile updates are available for review.',
        severity: 'Synced',
        timestamp: now.subtract(const Duration(hours: 2, minutes: 12)),
        icon: Icons.cloud_done_rounded,
        color: const Color(0xFF22D3EE),
      ),
    ];

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Recent Alerts'), backgroundColor: Colors.transparent),
        body: ListView.separated(
          padding: const EdgeInsets.all(18),
          itemCount: alerts.length + 1,
          separatorBuilder: (_, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == 0) {
              return GlassCard(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.notifications_active_rounded, color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Demo alert log', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text(
                            'Static monitoring events for evaluation.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            final alert = alerts[index - 1];
            return GlassCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: alert.color.withValues(alpha: .16),
                  child: Icon(alert.icon, color: alert.color),
                ),
                title: Text(alert.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${alert.body}\n${DateFormat.yMMMd().add_jm().format(alert.timestamp)}'),
                trailing: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(alert.severity),
                  side: BorderSide(color: alert.color.withValues(alpha: .32)),
                  backgroundColor: alert.color.withValues(alpha: .10),
                ),
                isThreeLine: true,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DemoAlert {
  const _DemoAlert({
    required this.title,
    required this.body,
    required this.severity,
    required this.timestamp,
    required this.icon,
    required this.color,
  });

  final String title;
  final String body;
  final String severity;
  final DateTime timestamp;
  final IconData icon;
  final Color color;
}
