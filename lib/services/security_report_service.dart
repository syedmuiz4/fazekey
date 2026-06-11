import 'dart:io';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/access_log.dart';
import '../models/room_access_record.dart';

class SecurityReportService {
  Future<File> writeCsvReport(List<AccessLog> logs) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        'campus-access-security-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}.csv';
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(buildCsv(logs), flush: true);
    return file;
  }

  Future<File> writeRoomHistoryReport(List<RoomAccessRecord> records) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        'room-history-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}.csv';
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(buildRoomHistoryCsv(records), flush: true);
    return file;
  }

  String buildCsv(List<AccessLog> logs) {
    final rows = [
      ['id', 'timestamp', 'status', 'user', 'room', 'reason', 'synced'],
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

  String buildRoomHistoryCsv(List<RoomAccessRecord> records) {
    final sessions = _roomSessions(records);
    final rows = [
      [
        'session_id',
        'user',
        'room',
        'entry_time',
        'exit_time',
        'duration_minutes',
        'status',
        'entry_reason',
        'exit_reason',
      ],
      for (final session in sessions)
        [
          _clean(session.sessionId),
          _clean(session.userName),
          _clean(session.roomName),
          DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(session.entryAt),
          session.exitAt == null
              ? ''
              : DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(session.exitAt!),
          session.duration.inMinutes.toString(),
          session.open ? 'OPEN' : 'CLOSED',
          _clean(session.entryReason),
          _clean(session.exitReason),
        ],
    ];
    return const ListToCsvConverter().convert(rows);
  }

  List<_RoomSessionReportRow> _roomSessions(List<RoomAccessRecord> records) {
    final sorted = records.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final entries = <String, RoomAccessRecord>{};
    final rows = <_RoomSessionReportRow>[];
    for (final record in sorted) {
      if (record.isEntry) {
        entries[record.sessionId] = record;
        continue;
      }
      final entry = entries.remove(record.sessionId);
      if (entry == null) continue;
      rows.add(_RoomSessionReportRow(entry: entry, exit: record));
    }
    for (final entry in entries.values) {
      rows.add(_RoomSessionReportRow(entry: entry));
    }
    rows.sort((a, b) => b.entryAt.compareTo(a.entryAt));
    return rows;
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

class _RoomSessionReportRow {
  const _RoomSessionReportRow({required this.entry, this.exit});

  final RoomAccessRecord entry;
  final RoomAccessRecord? exit;

  String get sessionId => entry.sessionId;
  String get userName => entry.userName;
  String get roomName => entry.areaName;
  DateTime get entryAt => entry.timestamp;
  DateTime? get exitAt => exit?.timestamp;
  Duration get duration => (exitAt ?? DateTime.now()).difference(entryAt);
  bool get open => exit == null;
  String get entryReason => entry.reason;
  String get exitReason => exit?.reason ?? '';
}
