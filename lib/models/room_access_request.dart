import 'package:cloud_firestore/cloud_firestore.dart';

class RoomAccessRequest {
  const RoomAccessRequest({
    required this.id,
    required this.userId,
    required this.userName,
    required this.areaId,
    required this.areaName,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String userName;
  final String areaId;
  final String areaName;
  final String status;
  final DateTime createdAt;

  bool get isOpen => status == 'open';

  factory RoomAccessRequest.fromMap(String id, Map<String, dynamic> map) {
    return RoomAccessRequest(
      id: id,
      userId: (map['userId'] ?? '').toString(),
      userName: (map['userName'] ?? '').toString(),
      areaId: (map['areaId'] ?? '').toString(),
      areaName: (map['areaName'] ?? '').toString(),
      status: (map['status'] ?? 'open').toString(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'userName': userName,
    'areaId': areaId,
    'areaName': areaName,
    'status': status,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}
