import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fazekey/main.dart' as app;
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

  test('room ACL explicit grant and revoke override broad policy', () {
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
      accessLevel: 1,
    );
    final area = Area(
      id: 'it-room',
      name: 'IT Room',
      location: 'FSKTM',
      floor: 'Level 3',
      roomNumber: '33',
      active: true,
      createdAt: DateTime(2026),
      allowedDepartments: const ['Information Security'],
      allowedRoles: const ['Security'],
      currentOccupancy: 0,
      capacity: 10,
    );

    expect(user.canAccessArea(area), isFalse);
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
  });

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
      accessLevel: 1,
    );
    final admin = user.copyWith(role: 'admin');
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
    });

    expect(user.identityNumber, 'AI220001');
    expect(user.course, 'Bachelor of Software Engineering');
    expect(user.faculty, 'FSKTM');
    expect(user.currentSemester, 'Semester 5');
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
