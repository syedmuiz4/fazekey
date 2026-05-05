import 'dart:io';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/access_log.dart';

class SecurityReportService {
  Future<File> writeCsvReport(List<AccessLog> logs) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        'facekey-security-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}.csv';
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(buildCsv(logs), flush: true);
    return file;
  }

  String buildCsv(List<AccessLog> logs) {
    final rows = [
      [
        'id',
        'timestamp',
        'status',
        'user',
        'area',
        'reason',
        'synced',
      ],
      for (final log in logs)
        [
          _clean(log.id),
          DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(log.timestamp),
          _clean(log.status.toUpperCase()),
          _clean(log.userName),
          _clean(log.areaName),
          _clean(log.reason),
          log.synced ? 'yes' : 'no',
        ],
    ];
    return const ListToCsvConverter().convert(rows);
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
