import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/security_alert.dart';
import '../providers/alert_provider.dart';
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
        body: alerts.isEmpty
            ? const _EmptyAlerts()
            : ListView.separated(
                padding: const EdgeInsets.all(18),
                itemCount: alerts.length,
                separatorBuilder: (_, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _AlertCard(alert: alerts[index]),
              ),
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
