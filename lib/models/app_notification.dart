import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    required this.read,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final DateTime createdAt;
  final bool read;

  factory AppNotification.fromMap(String id, Map<String, dynamic> map) => AppNotification(
        id: id,
        title: map['title'] ?? '',
        body: map['body'] ?? '',
        type: map['type'] ?? 'system',
        createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        read: map['read'] ?? false,
      );
}
