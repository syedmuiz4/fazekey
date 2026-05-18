import 'dart:io';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_user.dart';

class UserDataExportService {
  Future<File> writeCsv(List<AppUser> users) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        'campus-access-users-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}.csv';
    final file = File(p.join(dir.path, fileName));
    final rows = [
      [
        'profile_id',
        'identity_number',
        'name',
        'email',
        'department',
        'course',
        'faculty',
        'current_semester',
        'phone',
        'home_address',
        'emergency_contact',
        'restricted_room',
        'role',
        'access_level',
        'face_registered',
        'created_at',
      ],
      for (final user in users)
        [
          _clean(user.id),
          _clean(user.identityNumber),
          _clean(user.name),
          _clean(user.email),
          _clean(user.department),
          _clean(user.course),
          _clean(user.faculty),
          _clean(user.currentSemester),
          _clean(user.phone),
          _clean(user.homeAddress),
          _clean(user.emergencyContact),
          _clean(user.assignedRoomsLabel),
          _clean(user.role),
          user.accessLevel,
          user.hasFace ? 'yes' : 'no',
          DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(user.createdAt),
        ],
    ];
    await file.writeAsString(
      const ListToCsvConverter().convert(rows),
      flush: true,
    );
    return file;
  }

  String _clean(String value) {
    return value
        .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), ' ')
        .replaceAll(RegExp(r'\\[rnt]'), ' ')
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
