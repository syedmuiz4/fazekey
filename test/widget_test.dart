import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fazekey/main.dart' as app;
import 'package:fazekey/models/access_grant.dart';
import 'package:fazekey/models/access_log.dart';
import 'package:fazekey/models/app_user.dart';
import 'package:fazekey/models/area.dart';
import 'package:fazekey/models/system_settings.dart';
import 'package:fazekey/services/security_report_service.dart';

void main() {
  test('access window permits weekdays from 08:00 until before 10:00', () {
    expect(
      SystemSettings.isAccessAllowedAt(DateTime(2026, 5, 4, 9, 5)),
      isTrue,
    );
    expect(SystemSettings.isAccessAllowedAt(DateTime(2026, 5, 4, 8)), isTrue);
    expect(
      SystemSettings.isAccessAllowedAt(DateTime(2026, 5, 4, 9, 59)),
      isTrue,
    );
  });

  test('access window denies weekends and times outside 08:00-10:00', () {
    expect(
      SystemSettings.isAccessAllowedAt(DateTime(2026, 5, 4, 7, 59)),
      isFalse,
    );
    expect(SystemSettings.isAccessAllowedAt(DateTime(2026, 5, 4, 10)), isFalse);
    expect(
      SystemSettings.isAccessAllowedAt(DateTime(2026, 5, 9, 11, 5)),
      isFalse,
    );
    expect(
      SystemSettings.isAccessAllowedAt(DateTime(2026, 5, 10, 11, 5)),
      isFalse,
    );
  });

  test('after hours toggle controls scan denial policy', () {
    final disabled = SystemSettings.defaults();
    final enabled = disabled.copyWith(afterHoursAlerts: true);

    expect(disabled.shouldDenyScanAt(DateTime(2026, 5, 9, 11, 5)), isFalse);
    expect(enabled.shouldDenyScanAt(DateTime(2026, 5, 9, 11, 5)), isTrue);
    expect(enabled.shouldDenyScanAt(DateTime(2026, 5, 4, 9, 5)), isFalse);
    expect(enabled.shouldDenyScanAt(DateTime(2026, 5, 5, 13, 12)), isTrue);
  });

  test('system config afterHoursEnabled drives lockout policy', () {
    final settings = SystemSettings.fromMap({
      'afterHoursEnabled': true,
      'accessWindowStart': 8,
      'accessWindowEnd': 10,
    });

    expect(settings.shouldDenyScanAt(DateTime(2026, 5, 5, 13, 12)), isTrue);
  });

  test('admin role bypasses operational timing restrictions', () {
    final settings = SystemSettings.defaults().copyWith(afterHoursAlerts: true);
    final afterHours = DateTime(2026, 5, 5, 13, 12);

    expect(settings.shouldDenyScanForRole('user', afterHours), isTrue);
    expect(settings.shouldDenyScanForRole('admin', afterHours), isFalse);
    expect(settings.shouldDenyScanForRole('Admin', afterHours), isFalse);
  });

  test(
    'room ACL user category maps legacy roles and revoke overrides access',
    () {
      final user = AppUser(
        id: 'user-1',
        identityNumber: 'AI220001',
        name: 'Test User',
        email: 'user@example.edu',
        department: 'Software Engineering',
        phone: '',
        room: 'IT Room',
        role: 'user',
        createdAt: DateTime(2026),
        hasFace: true,
        accessLevel: 3,
      );
      final area = Area(
        id: 'it-room',
        name: 'IT Room',
        location: 'FSKTM',
        floor: 'Level 3',
        roomNumber: '33',
        active: true,
        createdAt: DateTime(2026),
        allowedDepartments: const ['Software Engineering'],
        allowedRoles: const ['Security'],
        currentOccupancy: 0,
        capacity: 10,
      );

      expect(user.canAccessArea(area), isTrue);
      expect(
        user.canAccessArea(area.copyWith(allowedUserIds: [user.id])),
        isTrue,
      );
      expect(
        user.canAccessArea(
          area.copyWith(allowedUserIds: [user.id], revokedUserIds: [user.id]),
        ),
        isFalse,
      );
    },
  );

  test('room capacity blocks non-privileged users when full', () {
    final user = AppUser(
      id: 'user-1',
      identityNumber: 'AI220001',
      name: 'Test User',
      email: 'user@example.edu',
      department: 'Software Engineering',
      phone: '',
      room: 'Level 1 - Access Lab',
      role: 'user',
      createdAt: DateTime(2026),
      hasFace: true,
      accessLevel: 3,
    );
    final admin = user.copyWith(role: 'Admin');
    final fullArea = Area(
      id: 'lab',
      name: 'Level 1 - Access Lab',
      location: 'FSKTM',
      floor: 'Level 1',
      roomNumber: '31',
      active: true,
      createdAt: DateTime(2026),
      allowedDepartments: const ['Software Engineering'],
      allowedRoles: const ['User'],
      currentOccupancy: 20,
      capacity: 20,
    );

    expect(user.canAccessArea(fullArea), isFalse);
    expect(admin.canAccessArea(fullArea), isTrue);
    expect(user.copyWith(role: ' admin ').canAccessArea(fullArea), isTrue);
  });

  test('admin registered access bypasses room match and capacity checks', () {
    final admin = AppUser(
      id: 'admin-1',
      identityNumber: 'AD220001',
      name: 'Admin User',
      email: 'admin@example.edu',
      department: 'Software Engineering',
      phone: '',
      room: '',
      role: 'Admin',
      createdAt: DateTime(2026),
      hasFace: true,
      accessLevel: 3,
    );
    final fullArea = Area(
      id: 'lab',
      name: 'Level 1 - Access Lab',
      location: 'FSKTM',
      floor: 'Level 1',
      roomNumber: '31',
      active: true,
      createdAt: DateTime(2026),
      allowedDepartments: const ['Software Engineering'],
      allowedRoles: const ['User'],
      currentOccupancy: 20,
      capacity: 20,
    );

    expect(admin.isRegisteredForArea(fullArea), isFalse);
    expect(admin.canAccessRegisteredArea(fullArea), isTrue);
    expect(
      admin.copyWith(role: ' admin ').canAccessRegisteredArea(fullArea),
      isTrue,
    );
  });

  test('approved User role can access any active User room', () {
    final user = AppUser(
      id: 'user-1',
      identityNumber: 'AI220001',
      name: 'Test User',
      email: 'user@example.edu',
      department: 'Software Engineering',
      phone: '',
      room: 'Different Room',
      role: 'User',
      status: 'approved',
      createdAt: DateTime(2026),
      hasFace: true,
      accessLevel: 1,
    );
    final area = Area(
      id: 'lab',
      name: 'Level 1 - Access Lab',
      location: 'FSKTM',
      floor: 'Level 1',
      roomNumber: '31',
      active: true,
      createdAt: DateTime(2026),
      allowedDepartments: const [],
      allowedRoles: const [' User '],
      currentOccupancy: 0,
      capacity: 20,
    );

    expect(user.canAccessArea(area), isTrue);
  });

  test('pending non-admin users require admin verification before access', () {
    final user = AppUser(
      id: 'user-1',
      identityNumber: 'AI220001',
      name: 'Pending User',
      email: 'pending@example.edu',
      department: 'Software Engineering',
      phone: '',
      room: 'Level 1 - Access Lab',
      role: 'User',
      status: 'pending',
      createdAt: DateTime(2026),
      hasFace: true,
      accessLevel: 3,
    );
    final area = Area(
      id: 'lab',
      name: 'Level 1 - Access Lab',
      location: 'FSKTM',
      floor: 'Level 1',
      roomNumber: '31',
      active: true,
      createdAt: DateTime(2026),
      allowedDepartments: const ['Software Engineering'],
      allowedRoles: const ['User'],
      currentOccupancy: 0,
      capacity: 20,
    );

    expect(user.canAccessArea(area), isFalse);
    expect(user.canAccessRegisteredArea(area), isFalse);
  });

  test('admin bypass ignores approval status and room checks', () {
    final admin = AppUser(
      id: 'admin-1',
      identityNumber: 'AD220001',
      name: 'Pending Admin',
      email: 'admin@example.edu',
      department: 'Software Engineering',
      phone: '',
      room: '',
      role: 'Admin',
      status: 'pending',
      createdAt: DateTime(2026),
      hasFace: true,
      accessLevel: 1,
    );
    final inactiveArea = Area(
      id: 'lab',
      name: 'Level 1 - Access Lab',
      location: 'FSKTM',
      floor: 'Level 1',
      roomNumber: '31',
      active: false,
      createdAt: DateTime(2026),
      allowedDepartments: const [],
      allowedRoles: const [],
      currentOccupancy: 20,
      capacity: 20,
    );

    expect(admin.canAccessArea(inactiveArea), isTrue);
    expect(admin.canAccessRegisteredArea(inactiveArea), isTrue);
  });

  test(
    'room matching normalizes Firestore room field and requires active room',
    () {
      final user = AppUser(
        id: 'user-1',
        identityNumber: 'AI220001',
        name: 'Test User',
        email: 'user@example.edu',
        department: 'Software Engineering',
        phone: '',
        room: '  level 1 - access lab ',
        role: 'User',
        createdAt: DateTime(2026),
        hasFace: true,
        accessLevel: 1,
      );
      final activeArea = Area(
        id: 'lab',
        name: 'Level 1 - Access Lab',
        location: 'FSKTM',
        floor: 'Level 1',
        roomNumber: '31',
        active: true,
        createdAt: DateTime(2026),
        allowedDepartments: const ['Software Engineering'],
        allowedRoles: const ['User'],
        currentOccupancy: 0,
        capacity: 20,
      );

      expect(user.isRegisteredForArea(activeArea), isTrue);
      expect(user.canAccessRegisteredArea(activeArea), isTrue);
      expect(
        user.canAccessRegisteredArea(activeArea.copyWith(active: false)),
        isFalse,
      );
    },
  );

  test('room matching ignores case and spaces in scanner area label', () {
    final user = AppUser(
      id: 'user-35',
      identityNumber: 'AI220035',
      name: 'Room 35 User',
      email: 'room35@example.edu',
      department: 'Software Engineering',
      phone: '',
      room: 'level 3-room 35',
      role: 'User',
      createdAt: DateTime(2026),
      hasFace: true,
      accessLevel: 3,
    );
    final scannerArea = Area(
      id: 'room-35',
      name: '',
      location: 'FSKTM',
      floor: 'Level 3',
      roomNumber: '35',
      active: true,
      createdAt: DateTime(2026),
      allowedDepartments: const ['Software Engineering'],
      allowedRoles: const ['User'],
      currentOccupancy: 0,
      capacity: 20,
    );

    expect(user.isRegisteredForArea(scannerArea), isTrue);
    expect(user.canAccessRegisteredArea(scannerArea), isTrue);
    expect(
      user.canAccessRegisteredArea(scannerArea.copyWith(active: false)),
      isFalse,
    );
  });

  test('multi-room users can match any assigned active room', () {
    final user = AppUser(
      id: 'user-multi',
      identityNumber: 'AI220099',
      name: 'Multi Room User',
      email: 'multi@example.edu',
      department: 'Information Security',
      phone: '',
      room: 'Server Room 1',
      rooms: const ['Server Room 1', 'IT Lab', 'KPI Room'],
      role: 'User',
      createdAt: DateTime(2026),
      hasFace: true,
      accessLevel: 3,
    );
    final itLab = Area(
      id: 'it-lab',
      name: 'IT Lab',
      location: 'FSKTM',
      floor: 'Level 3',
      roomNumber: '33',
      active: true,
      createdAt: DateTime(2026),
      allowedDepartments: const ['Information Security'],
      allowedRoles: const ['User'],
      currentOccupancy: 0,
      capacity: 20,
    );

    expect(user.assignedRooms, ['Server Room 1', 'IT Lab', 'KPI Room']);
    expect(user.isRegisteredForArea(itLab), isTrue);
    expect(user.canAccessRegisteredArea(itLab), isTrue);
    expect(user.toMap()['rooms'], ['Server Room 1', 'IT Lab', 'KPI Room']);
  });

  test('temporal access grant reports active, future, and expired windows', () {
    final grant = AccessGrant(
      id: 'grant-1',
      userId: 'user-1',
      userName: 'Test User',
      userPosition: 'Student',
      areaId: 'server-room',
      areaName: 'Server Room',
      startAt: DateTime(2026, 5),
      endAt: DateTime(2026, 6),
      active: true,
      createdAt: DateTime(2026, 4),
    );

    expect(grant.startsLaterThan(DateTime(2026, 4, 30)), isTrue);
    expect(grant.isActiveAt(DateTime(2026, 5, 18)), isTrue);
    expect(grant.isExpiredAt(DateTime(2026, 6)), isTrue);
    expect(grant.isActiveAt(DateTime(2026, 6)), isFalse);
  });

  test('area reads isActive Firestore status alias', () {
    final area = Area.fromMap('lab', {
      'name': 'Level 1 - Access Lab',
      'location': 'FSKTM',
      'floor': 'Level 1',
      'roomNumber': '31',
      'isActive': false,
      'allowedDepartments': const ['Software Engineering'],
      'allowedRoles': const ['User'],
      'currentOccupancy': 0,
      'capacity': 20,
    });

    expect(area.active, isFalse);
    expect(area.toMap()['isActive'], isFalse);
  });

  test('only explicit admin role enables admin routing', () {
    final base = AppUser(
      id: 'user-1',
      identityNumber: 'AI220001',
      name: 'Test User',
      email: 'user@example.edu',
      department: 'Software Engineering',
      phone: '',
      room: 'Level 1 - Access Lab',
      role: 'user',
      createdAt: DateTime(2026),
      hasFace: true,
      accessLevel: 1,
    );

    expect(base.isAdmin, isFalse);
    expect(base.copyWith(role: 'Admin').isAdmin, isTrue);
    expect(base.copyWith(role: 'Security').isAdmin, isFalse);
    expect(base.copyWith(role: 'Security').roleLabel, 'Student');
    expect(base.copyWith(role: 'Security').toMap()['role'], 'User');
  });

  test('app user reads student passport fields from Firestore map', () {
    final user = AppUser.fromMap('student-1', {
      'name': 'Nur Aina',
      'email': 'aina@example.edu',
      'identityNumber': 'AI220001',
      'course': 'Bachelor of Software Engineering',
      'faculty': 'FSKTM',
      'currentSemester': 'Semester 5',
      'department': 'Software Engineering',
      'phone': '',
      'room': 'IT Room',
      'role': 'user',
      'hasFace': true,
      'accessLevel': 3,
      'status': 'pending',
      'position': 'Staff',
    });

    expect(user.identityNumber, 'AI220001');
    expect(user.course, 'Bachelor of Software Engineering');
    expect(user.faculty, 'FSKTM');
    expect(user.currentSemester, 'Semester 5');
    expect(user.status, 'pending');
    expect(user.role, 'user');
    expect(user.roleLabel, 'Staff');
    expect(user.toMap()['role'], 'User');
    expect(user.toMap()['position'], 'Staff');
    expect(user.toMap()['status'], 'pending');
  });

  test('security report CSV sanitizes escaped and control characters', () {
    final csv = SecurityReportService().buildCsv([
      AccessLog(
        id: 'log-1',
        userId: 'user-1',
        userName: 'Ada \x1B[31m\nLovelace',
        areaId: 'area-1',
        areaName: 'Lab\rWing',
        status: 'denied',
        reason: r'Door\nforced \t open',
        timestamp: DateTime(2026, 5, 5, 13, 12),
        synced: true,
      ),
    ]);

    expect(csv, isNot(contains('\x1B')));
    expect(csv, isNot(contains('[31m')));
    expect(csv, isNot(contains(r'\n')));
    expect(csv, contains('Ada Lovelace'));
    expect(csv, contains('Door forced open'));
  });

  test('FaceKey project smoke test', () {
    expect('FaceKey'.isNotEmpty, isTrue);
    expect(app.FaceKeyApp, isNotNull);
  });

  test('logo asset is bundled', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final data = await rootBundle.load('assets/images/logo2.png');

    expect(data.lengthInBytes, greaterThan(0));
  });

  testWidgets('logo image renders from asset path', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Image.asset('assets/images/logo2.png'))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
