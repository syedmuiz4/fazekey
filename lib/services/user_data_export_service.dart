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
        'facekey-users-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}.csv';
    final file = File(p.join(dir.path, fileName));
    final rows = [
      [
        'id',
        'name',
        'email',
        'department',
        'phone',
        'restricted_area',
        'role',
        'face_registered',
        'created_at',
      ],
      for (final user in users)
        [
          user.id,
          user.name,
          user.email,
          user.department,
          user.phone,
          user.room,
          user.role,
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
}
