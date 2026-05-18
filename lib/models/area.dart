import 'package:cloud_firestore/cloud_firestore.dart';

class Area {
  const Area({
    required this.id,
    required this.name,
    required this.location,
    required this.floor,
    required this.roomNumber,
    required this.active,
    required this.createdAt,
    required this.allowedDepartments,
    required this.allowedRoles,
    this.allowedUserIds = const [],
    this.revokedUserIds = const [],
    required this.currentOccupancy,
    required this.capacity,
  });

  final String id;
  final String name;
  final String location;
  final String floor;
  final String roomNumber;
  final bool active;
  final DateTime createdAt;
  final List<String> allowedDepartments;
  final List<String> allowedRoles;
  final List<String> allowedUserIds;
  final List<String> revokedUserIds;
  final int currentOccupancy;
  final int capacity;

  bool get allowsUserRole =>
      allowedRoles.any((role) => role.trim().toLowerCase() == 'user');

  factory Area.fromMap(String id, Map<String, dynamic> map) => Area(
    id: id,
    name: map['name'] ?? '',
    location: map['location'] ?? '',
    floor: map['floor'] ?? '',
    roomNumber: map['roomNumber'] ?? '',
    active: (map['isActive'] ?? map['active']) ?? true,
    createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    allowedDepartments: List<String>.from(
      map['allowedDepartments'] ?? const [],
    ),
    allowedRoles: List<String>.from(map['allowedRoles'] ?? const []),
    allowedUserIds: List<String>.from(map['allowedUserIds'] ?? const []),
    revokedUserIds: List<String>.from(map['revokedUserIds'] ?? const []),
    currentOccupancy: map['currentOccupancy'] ?? 0,
    capacity: map['capacity'] ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'location': location,
    'floor': floor,
    'roomNumber': roomNumber,
    'active': active,
    'isActive': active,
    'createdAt': Timestamp.fromDate(createdAt),
    'allowedDepartments': allowedDepartments,
    'allowedRoles': allowedRoles,
    'allowedUserIds': allowedUserIds,
    'revokedUserIds': revokedUserIds,
    'currentOccupancy': currentOccupancy,
    'capacity': capacity,
  };

  Area copyWith({
    String? name,
    String? location,
    String? floor,
    String? roomNumber,
    bool? active,
    List<String>? allowedDepartments,
    List<String>? allowedRoles,
    List<String>? allowedUserIds,
    List<String>? revokedUserIds,
    int? currentOccupancy,
    int? capacity,
  }) => Area(
    id: id,
    name: name ?? this.name,
    location: location ?? this.location,
    floor: floor ?? this.floor,
    roomNumber: roomNumber ?? this.roomNumber,
    active: active ?? this.active,
    createdAt: createdAt,
    allowedDepartments: allowedDepartments ?? this.allowedDepartments,
    allowedRoles: allowedRoles ?? this.allowedRoles,
    allowedUserIds: allowedUserIds ?? this.allowedUserIds,
    revokedUserIds: revokedUserIds ?? this.revokedUserIds,
    currentOccupancy: currentOccupancy ?? this.currentOccupancy,
    capacity: capacity ?? this.capacity,
  );
}
