import 'package:cloud_firestore/cloud_firestore.dart';

class AccessGrant {
  const AccessGrant({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userPosition,
    required this.areaId,
    required this.areaName,
    required this.startAt,
    required this.endAt,
    required this.active,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String userName;
  final String userPosition;
  final String areaId;
  final String areaName;
  final DateTime startAt;
  final DateTime endAt;
  final bool active;
  final DateTime createdAt;

  bool isActiveAt(DateTime moment) =>
      active && !moment.isBefore(startAt) && moment.isBefore(endAt);

  bool isExpiredAt(DateTime moment) => active && !moment.isBefore(endAt);

  bool startsLaterThan(DateTime moment) => active && moment.isBefore(startAt);

  factory AccessGrant.fromMap(String id, Map<String, dynamic> map) {
    return AccessGrant(
      id: id,
      userId: (map['userId'] ?? '').toString(),
      userName: (map['userName'] ?? '').toString(),
      userPosition: (map['userPosition'] ?? '').toString(),
      areaId: (map['areaId'] ?? '').toString(),
      areaName: (map['areaName'] ?? '').toString(),
      startAt: (map['startAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endAt:
          (map['endAt'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(days: 1)),
      active: map['active'] ?? true,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'userName': userName,
    'userPosition': userPosition,
    'areaId': areaId,
    'areaName': areaName,
    'startAt': Timestamp.fromDate(startAt),
    'endAt': Timestamp.fromDate(endAt),
    'active': active,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}

class AccessGrantEvaluation {
  const AccessGrantEvaluation({
    required this.granted,
    required this.expired,
    this.grant,
  });

  final bool granted;
  final bool expired;
  final AccessGrant? grant;

  bool get pending => !granted && !expired && grant != null;

  static const none = AccessGrantEvaluation(granted: false, expired: false);
}
