import 'package:cloud_firestore/cloud_firestore.dart';

class AccessLog {
  const AccessLog({
    required this.id,
    required this.userId,
    required this.userName,
    required this.areaId,
    required this.areaName,
    required this.status,
    required this.reason,
    required this.timestamp,
    required this.synced,
    this.snapshotPath,
  });

  final String id;
  final String userId;
  final String userName;
  final String areaId;
  final String areaName;
  final String status;
  final String reason;
  final DateTime timestamp;
  final bool synced;
  final String? snapshotPath;

  bool get granted => status == 'granted';
  bool get isUnknownFace =>
      userId.isEmpty || userName.toLowerCase() == 'unknown face';

  factory AccessLog.fromMap(String id, Map<String, dynamic> map) => AccessLog(
    id: id,
    userId: map['userId'] ?? '',
    userName: map['userName'] ?? 'Unknown',
    areaId: map['areaId'] ?? '',
    areaName: map['areaName'] ?? 'No active room configured',
    status: map['status'] ?? 'denied',
    reason: map['reason'] ?? '',
    timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    synced: map['synced'] ?? true,
    snapshotPath: map['snapshotPath'],
  );

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'userName': userName,
    'areaId': areaId,
    'areaName': areaName,
    'status': status,
    'reason': reason,
    'timestamp': Timestamp.fromDate(timestamp),
    'synced': synced,
    if (snapshotPath != null) 'snapshotPath': snapshotPath,
  };
}
