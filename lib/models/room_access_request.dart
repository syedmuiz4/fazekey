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
    this.expiresAt,
    this.exitedPreviousRoom = false,
    this.previousRoomName = '',
  });

  final String id;
  final String userId;
  final String userName;
  final String areaId;
  final String areaName;
  final String status;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool exitedPreviousRoom;
  final String previousRoomName;

  bool get isOpen =>
      status == 'open' &&
      (expiresAt == null || DateTime.now().isBefore(expiresAt!));

  factory RoomAccessRequest.fromMap(String id, Map<String, dynamic> map) {
    return RoomAccessRequest(
      id: id,
      userId: (map['userId'] ?? '').toString(),
      userName: (map['userName'] ?? '').toString(),
      areaId: (map['areaId'] ?? '').toString(),
      areaName: (map['areaName'] ?? '').toString(),
      status: (map['status'] ?? 'open').toString(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (map['expiresAt'] as Timestamp?)?.toDate(),
      exitedPreviousRoom: map['exitedPreviousRoom'] == true,
      previousRoomName: (map['previousRoomName'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'userName': userName,
    'areaId': areaId,
    'areaName': areaName,
    'status': status,
    'createdAt': Timestamp.fromDate(createdAt),
    if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
    'exitedPreviousRoom': exitedPreviousRoom,
    'previousRoomName': previousRoomName,
  };
}
