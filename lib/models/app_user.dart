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
    this.rooms = const [],
    this.identityNumber = '',
    this.course = '',
    this.faculty = '',
    this.currentSemester = '',
    this.accessLevel = 1,
    this.status = 'approved',
    this.position = 'Student',
    this.homeAddress = '',
    this.emergencyContact = '',
    this.photoUrl,
    this.pendingPhotoUrl,
    this.photoChangeRequestedAt,
    this.photoUpdatedAt,
    this.requiresPasswordChange = false,
    this.isNewTemporaryPasswordAccount = false,
    this.temporaryPasswordIssuedAt,
    this.temporaryPasswordExpiresAt,
    this.accessValidFrom,
    this.accessValidUntil,
  });

  final String id;
  final String name;
  final String email;
  final String department;
  final String phone;
  final String room;
  final List<String> rooms;
  final String role;
  final DateTime createdAt;
  final bool hasFace;
  final String identityNumber;
  final String course;
  final String faculty;
  final String currentSemester;
  final int accessLevel;
  final String status;
  final String position;
  final String homeAddress;
  final String emergencyContact;
  final String? photoUrl;
  final String? pendingPhotoUrl;
  final DateTime? photoChangeRequestedAt;
  final DateTime? photoUpdatedAt;
  final bool requiresPasswordChange;
  final bool isNewTemporaryPasswordAccount;
  final DateTime? temporaryPasswordIssuedAt;
  final DateTime? temporaryPasswordExpiresAt;
  final DateTime? accessValidFrom;
  final DateTime? accessValidUntil;

  bool get isAdmin =>
      role.trim().toLowerCase() == 'admin' ||
      _accessKey(name).contains(_accessKey('Dr. MOHD ZANES BIN SAHID'));
  bool get isApproved => status.trim().toLowerCase() == 'approved';
  bool get isPending => status.trim().toLowerCase() == 'pending';
  bool get hasPendingPhotoApproval =>
      pendingPhotoUrl?.trim().isNotEmpty == true;

  List<String> get assignedRooms {
    final labels = <String>[];
    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      if (labels.any((label) => _accessKey(label) == _accessKey(trimmed))) {
        return;
      }
      labels.add(trimmed);
    }

    add(room);
    for (final assigned in rooms) {
      add(assigned);
    }
    return labels;
  }

  String get assignedRoomsLabel {
    final assigned = assignedRooms;
    return assigned.isEmpty ? '' : assigned.join(', ');
  }

  String get roleLabel {
    final normalized = role.trim().toLowerCase();
    if (normalized == 'admin') return 'Admin';
    final normalizedPosition = position.trim();
    return normalizedPosition.isEmpty ? 'User' : normalizedPosition;
  }

  String get backendRole => isAdmin ? 'Admin' : 'User';

  bool canAccessArea(Area area) {
    if (!isApproved) return false;
    if (!area.active) return false;
    if (area.revokedUserIds.contains(id)) return false;
    if (area.capacity > 0 && area.currentOccupancy >= area.capacity) {
      return false;
    }
    if (area.allowedUserIds.contains(id)) return true;
    if (_normalizedRole == 'user' && area.allowsUserRole) {
      return true;
    }
    final departmentAllowed =
        area.allowedDepartments.isEmpty ||
        area.allowedDepartments.any(
          (d) => d.trim().toLowerCase() == department.trim().toLowerCase(),
        );
    final roleKeys = {
      _normalizedRole,
      roleLabel.trim().toLowerCase(),
      position.trim().toLowerCase(),
      backendRole.trim().toLowerCase(),
    }..removeWhere((role) => role.isEmpty);
    final roleAllowed =
        area.allowedRoles.isEmpty ||
        area.allowedRoles.any((r) {
          final allowed = r.trim().toLowerCase();
          if (allowed.isEmpty) return true;
          if (allowed == 'user') return !isAdmin;
          if (allowed == 'security') {
            return !isAdmin || roleKeys.contains(allowed);
          }
          return roleKeys.contains(allowed);
        });
    final floorMatch = RegExp(r'(\d+)').firstMatch(area.floor);
    final floorLevel = int.tryParse(floorMatch?.group(1) ?? '');
    final levelAllowed = floorLevel == null || floorLevel <= accessLevel;
    return departmentAllowed && roleAllowed && levelAllowed;
  }

  bool isRegisteredForArea(Area area) {
    final registeredRooms = assignedRooms.map(_accessKey).toSet();
    if (registeredRooms.isEmpty) return false;
    final roomLabels = {
      area.id,
      area.name,
      area.roomNumber,
      '${area.floor} - ${area.name}',
      '${area.location} - ${area.name}',
      '${area.location} - ${area.floor} - ${area.name}',
      '${area.floor} - Room ${area.roomNumber}',
      '${area.location} - ${area.floor} - Room ${area.roomNumber}',
    }.map(_accessKey);
    return registeredRooms.any(roomLabels.contains);
  }

  bool canAccessRegisteredArea(Area area) {
    if (!isRegisteredForArea(area)) return false;
    return canAccessArea(area);
  }

  String get _normalizedRole => role.trim().toLowerCase();

  static String _accessKey(String value) =>
      value.trim().toLowerCase().replaceAll(' ', '');

  factory AppUser.fromMap(String id, Map<String, dynamic> map) {
    return AppUser(
      id: id,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      department: map['department'] ?? '',
      phone: map['phone'] ?? '',
      room: map['room'] ?? '',
      rooms: _readRooms(map),
      role: map['role'] ?? 'student',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      hasFace: map['hasFace'] ?? false,
      identityNumber: map['identityNumber'] ?? map['studentId'] ?? '',
      course: map['course'] ?? map['program'] ?? '',
      faculty: map['faculty'] ?? map['department'] ?? '',
      currentSemester: (map['currentSemester'] ?? map['semester'] ?? '')
          .toString(),
      accessLevel: (map['accessLevel'] as num?)?.toInt() ?? 1,
      status: (map['status'] ?? 'approved').toString(),
      position: (map['position'] ?? map['category'] ?? '').toString().isEmpty
          ? ((map['role'] ?? '').toString().trim().toLowerCase() == 'admin'
                ? 'Admin'
                : 'Student')
          : (map['position'] ?? map['category']).toString(),
      homeAddress: (map['homeAddress'] ?? map['address'] ?? '').toString(),
      emergencyContact: (map['emergencyContact'] ?? '').toString(),
      photoUrl: map['photoUrl'],
      pendingPhotoUrl: map['pendingPhotoUrl'],
      photoChangeRequestedAt: (map['photoChangeRequestedAt'] as Timestamp?)
          ?.toDate(),
      photoUpdatedAt: (map['photoUpdatedAt'] as Timestamp?)?.toDate(),
      requiresPasswordChange: map['requiresPasswordChange'] == true,
      isNewTemporaryPasswordAccount:
          map['isNewTemporaryPasswordAccount'] == true,
      temporaryPasswordIssuedAt:
          (map['temporaryPasswordIssuedAt'] as Timestamp?)?.toDate(),
      temporaryPasswordExpiresAt:
          (map['temporaryPasswordExpiresAt'] as Timestamp?)?.toDate(),
      accessValidFrom: (map['accessValidFrom'] as Timestamp?)?.toDate(),
      accessValidUntil: (map['accessValidUntil'] as Timestamp?)?.toDate(),
    );
  }

  static List<String> _readRooms(Map<String, dynamic> map) {
    final raw =
        map['rooms'] ??
        map['permittedZones'] ??
        map['roomAccess'] ??
        map['assignedRooms'];
    if (raw is Iterable) {
      return raw
          .map((room) => room.toString().trim())
          .where((room) => room.isNotEmpty)
          .toSet()
          .toList();
    }
    final room = (map['room'] ?? '').toString().trim();
    return room.isEmpty ? const [] : [room];
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'email': email,
    'department': department,
    'phone': phone,
    'room': assignedRooms.isEmpty ? room.trim() : assignedRooms.first,
    'rooms': assignedRooms,
    'permittedZones': assignedRooms,
    'role': backendRole,
    'identityNumber': identityNumber,
    'course': course,
    'faculty': faculty,
    'currentSemester': currentSemester,
    'accessLevel': accessLevel,
    'status': status,
    'position': position,
    'homeAddress': homeAddress,
    'emergencyContact': emergencyContact,
    'createdAt': Timestamp.fromDate(createdAt),
    'hasFace': hasFace,
    'photoUrl': photoUrl,
    if (pendingPhotoUrl?.trim().isNotEmpty == true)
      'pendingPhotoUrl': pendingPhotoUrl,
    if (photoChangeRequestedAt != null)
      'photoChangeRequestedAt': Timestamp.fromDate(photoChangeRequestedAt!),
    if (photoUpdatedAt != null)
      'photoUpdatedAt': Timestamp.fromDate(photoUpdatedAt!),
    'requiresPasswordChange': requiresPasswordChange,
    'isNewTemporaryPasswordAccount': isNewTemporaryPasswordAccount,
    if (temporaryPasswordIssuedAt != null)
      'temporaryPasswordIssuedAt': Timestamp.fromDate(
        temporaryPasswordIssuedAt!,
      ),
    if (temporaryPasswordExpiresAt != null)
      'temporaryPasswordExpiresAt': Timestamp.fromDate(
        temporaryPasswordExpiresAt!,
      ),
    if (accessValidFrom != null)
      'accessValidFrom': Timestamp.fromDate(accessValidFrom!),
    if (accessValidUntil != null)
      'accessValidUntil': Timestamp.fromDate(accessValidUntil!),
  };

  AppUser copyWith({
    String? name,
    String? email,
    String? department,
    String? phone,
    String? room,
    List<String>? rooms,
    String? role,
    String? identityNumber,
    String? course,
    String? faculty,
    String? currentSemester,
    int? accessLevel,
    String? status,
    String? position,
    String? homeAddress,
    String? emergencyContact,
    bool? hasFace,
    String? photoUrl,
    String? pendingPhotoUrl,
    DateTime? photoChangeRequestedAt,
    DateTime? photoUpdatedAt,
    bool? requiresPasswordChange,
    bool? isNewTemporaryPasswordAccount,
    DateTime? temporaryPasswordIssuedAt,
    DateTime? temporaryPasswordExpiresAt,
    DateTime? accessValidFrom,
    DateTime? accessValidUntil,
  }) => AppUser(
    id: id,
    name: name ?? this.name,
    email: email ?? this.email,
    department: department ?? this.department,
    phone: phone ?? this.phone,
    room: room ?? this.room,
    rooms: rooms ?? this.rooms,
    role: role ?? this.role,
    createdAt: createdAt,
    hasFace: hasFace ?? this.hasFace,
    identityNumber: identityNumber ?? this.identityNumber,
    course: course ?? this.course,
    faculty: faculty ?? this.faculty,
    currentSemester: currentSemester ?? this.currentSemester,
    accessLevel: accessLevel ?? this.accessLevel,
    status: status ?? this.status,
    position: position ?? this.position,
    homeAddress: homeAddress ?? this.homeAddress,
    emergencyContact: emergencyContact ?? this.emergencyContact,
    photoUrl: photoUrl ?? this.photoUrl,
    pendingPhotoUrl: pendingPhotoUrl ?? this.pendingPhotoUrl,
    photoChangeRequestedAt:
        photoChangeRequestedAt ?? this.photoChangeRequestedAt,
    photoUpdatedAt: photoUpdatedAt ?? this.photoUpdatedAt,
    requiresPasswordChange:
        requiresPasswordChange ?? this.requiresPasswordChange,
    isNewTemporaryPasswordAccount:
        isNewTemporaryPasswordAccount ?? this.isNewTemporaryPasswordAccount,
    temporaryPasswordIssuedAt:
        temporaryPasswordIssuedAt ?? this.temporaryPasswordIssuedAt,
    temporaryPasswordExpiresAt:
        temporaryPasswordExpiresAt ?? this.temporaryPasswordExpiresAt,
    accessValidFrom: accessValidFrom ?? this.accessValidFrom,
    accessValidUntil: accessValidUntil ?? this.accessValidUntil,
  );
}
