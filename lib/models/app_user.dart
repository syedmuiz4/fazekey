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
    this.identityNumber = '',
    this.course = '',
    this.faculty = '',
    this.currentSemester = '',
    this.accessLevel = 1,
    this.homeAddress = '',
    this.emergencyContact = '',
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
  final String identityNumber;
  final String course;
  final String faculty;
  final String currentSemester;
  final int accessLevel;
  final String homeAddress;
  final String emergencyContact;
  final String? photoUrl;

  bool get isAdmin => role.trim().toLowerCase() == 'admin';

  bool canAccessArea(Area area) {
    if (!area.active) return false;
    if (area.revokedUserIds.contains(id)) return false;
    if (area.allowedUserIds.contains(id)) return true;
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
    final floorMatch = RegExp(r'(\d+)').firstMatch(area.floor);
    final floorLevel = int.tryParse(floorMatch?.group(1) ?? '');
    final levelAllowed = floorLevel == null || floorLevel <= accessLevel;
    return departmentAllowed && roleAllowed && levelAllowed;
  }

  factory AppUser.fromMap(String id, Map<String, dynamic> map) {
    return AppUser(
      id: id,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      department: map['department'] ?? '',
      phone: map['phone'] ?? '',
      room: map['room'] ?? '',
      role: map['role'] ?? 'user',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      hasFace: map['hasFace'] ?? false,
      identityNumber: map['identityNumber'] ?? map['studentId'] ?? '',
      course: map['course'] ?? map['program'] ?? '',
      faculty: map['faculty'] ?? map['department'] ?? '',
      currentSemester: (map['currentSemester'] ?? map['semester'] ?? '')
          .toString(),
      accessLevel: (map['accessLevel'] as num?)?.toInt() ?? 1,
      homeAddress: (map['homeAddress'] ?? map['address'] ?? '').toString(),
      emergencyContact: (map['emergencyContact'] ?? '').toString(),
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
    'identityNumber': identityNumber,
    'course': course,
    'faculty': faculty,
    'currentSemester': currentSemester,
    'accessLevel': accessLevel,
    'homeAddress': homeAddress,
    'emergencyContact': emergencyContact,
    'createdAt': Timestamp.fromDate(createdAt),
    'hasFace': hasFace,
    'photoUrl': photoUrl,
  };

  AppUser copyWith({
    String? name,
    String? email,
    String? department,
    String? phone,
    String? room,
    String? role,
    String? identityNumber,
    String? course,
    String? faculty,
    String? currentSemester,
    int? accessLevel,
    String? homeAddress,
    String? emergencyContact,
    bool? hasFace,
    String? photoUrl,
  }) => AppUser(
    id: id,
    name: name ?? this.name,
    email: email ?? this.email,
    department: department ?? this.department,
    phone: phone ?? this.phone,
    room: room ?? this.room,
    role: role ?? this.role,
    createdAt: createdAt,
    hasFace: hasFace ?? this.hasFace,
    identityNumber: identityNumber ?? this.identityNumber,
    course: course ?? this.course,
    faculty: faculty ?? this.faculty,
    currentSemester: currentSemester ?? this.currentSemester,
    accessLevel: accessLevel ?? this.accessLevel,
    homeAddress: homeAddress ?? this.homeAddress,
    emergencyContact: emergencyContact ?? this.emergencyContact,
    photoUrl: photoUrl ?? this.photoUrl,
  );
}
