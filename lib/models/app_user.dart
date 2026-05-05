import 'package:cloud_firestore/cloud_firestore.dart';

import 'area.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.department,
    required this.phone,
    required this.room,
    required this.role,
    required this.createdAt,
    required this.hasFace,
    this.photoUrl,
  });

  final String id;
  final String name;
  final String email;
  final String department;
  final String phone;
  final String room;
  final String role;
  final DateTime createdAt;
  final bool hasFace;
  final String? photoUrl;

  bool canAccessArea(Area area) {
    if (!area.active) return false;
    final normalizedRole = role.trim().toLowerCase();
    if (normalizedRole == 'admin' || normalizedRole == 'security') return true;
    final departmentAllowed =
        area.allowedDepartments.isEmpty ||
        area.allowedDepartments.any(
          (d) => d.trim().toLowerCase() == department.trim().toLowerCase(),
        );
    final roleAllowed =
        area.allowedRoles.isEmpty ||
        area.allowedRoles.any((r) => r.trim().toLowerCase() == normalizedRole);
    return departmentAllowed && roleAllowed;
  }

  factory AppUser.fromMap(String id, Map<String, dynamic> map) {
    return AppUser(
      id: id,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      department: map['department'] ?? '',
      phone: map['phone'] ?? '',
      room: map['room'] ?? '',
      role: map['role'] ?? 'admin',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      hasFace: map['hasFace'] ?? false,
      photoUrl: map['photoUrl'],
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'email': email,
    'department': department,
    'phone': phone,
    'room': room,
    'role': role,
    'createdAt': Timestamp.fromDate(createdAt),
    'hasFace': hasFace,
    'photoUrl': photoUrl,
  };

  AppUser copyWith({
    String? name,
    String? department,
    String? phone,
    String? room,
    bool? hasFace,
    String? photoUrl,
  }) => AppUser(
    id: id,
    name: name ?? this.name,
    email: email,
    department: department ?? this.department,
    phone: phone ?? this.phone,
    room: room ?? this.room,
    role: role,
    createdAt: createdAt,
    hasFace: hasFace ?? this.hasFace,
    photoUrl: photoUrl ?? this.photoUrl,
  );
}
