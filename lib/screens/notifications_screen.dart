import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_notification.dart';
import '../services/firebase_service.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  static const route = '/notifications';

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Notifications'), backgroundColor: Colors.transparent),
        body: StreamBuilder<List<AppNotification>>(
          stream: FirebaseService().watchNotifications(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text(snapshot.error.toString()));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final items = snapshot.data!;
            if (items.isEmpty) return const Center(child: Text('No notifications yet'));
            return ListView.separated(
              padding: const EdgeInsets.all(18),
              itemCount: items.length,
              separatorBuilder: (_, index) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final n = items[i];
                return GlassCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(n.read ? Icons.notifications_none_rounded : Icons.notifications_active_rounded),
                    title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${n.body}\n${DateFormat.yMMMd().add_jm().format(n.createdAt)}'),
                    isThreeLine: true,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
