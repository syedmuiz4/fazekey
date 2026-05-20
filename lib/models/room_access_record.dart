import 'package:cloud_firestore/cloud_firestore.dart';

class RoomAccessRecord {
  const RoomAccessRecord({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.userName,
    required this.areaId,
    required this.areaName,
    required this.event,
    required this.timestamp,
    this.reason = '',
  });

  final String id;
  final String sessionId;
  final String userId;
  final String userName;
  final String areaId;
  final String areaName;
  final String event;
  final DateTime timestamp;
  final String reason;

  bool get isEntry => event == 'entry';
  bool get isExit => event == 'exit';

  factory RoomAccessRecord.fromMap(String id, Map<String, dynamic> map) {
    return RoomAccessRecord(
      id: id,
      sessionId: (map['sessionId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      userName: (map['userName'] ?? 'Unknown').toString(),
      areaId: (map['areaId'] ?? '').toString(),
      areaName: (map['areaName'] ?? 'No active room configured').toString(),
      event: (map['event'] ?? 'entry').toString(),
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reason: (map['reason'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'sessionId': sessionId,
    'userId': userId,
    'userName': userName,
    'areaId': areaId,
    'areaName': areaName,
    'event': event,
    'timestamp': Timestamp.fromDate(timestamp),
    'reason': reason,
  };
}
