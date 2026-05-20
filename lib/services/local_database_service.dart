import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/access_log.dart';

class LocalFaceMatch {
  const LocalFaceMatch({
    required this.userId,
    required this.name,
    required this.distance,
  });
  final String userId;
  final String name;
  final double distance;
}

class LocalDatabaseService {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'facekey.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE faces(
            userId TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            embedding TEXT NOT NULL,
            updatedAt INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pending_logs(
            id TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            createdAt INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<void> upsertFace({
    required String userId,
    required String name,
    required List<double> embedding,
  }) async {
    final db = await database;
    await db.insert('faces', {
      'userId': userId,
      'name': name,
      'embedding': jsonEncode(embedding),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> rekeyFace({
    required String fromUserId,
    required String toUserId,
    String? name,
  }) async {
    final from = fromUserId.trim();
    final to = toUserId.trim();
    if (from.isEmpty || to.isEmpty || from == to) return;
    final db = await database;
    final rows = await db.query(
      'faces',
      where: 'userId = ?',
      whereArgs: [from],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    await db.transaction((txn) async {
      await txn.insert('faces', {
        'userId': to,
        'name': name?.trim().isNotEmpty == true ? name!.trim() : row['name'],
        'embedding': row['embedding'],
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('faces', where: 'userId = ?', whereArgs: [from]);
    });
  }

  Future<void> deleteFace(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    final db = await database;
    await db.delete('faces', where: 'userId = ?', whereArgs: [id]);
  }

  Future<LocalFaceMatch?> findNearestFace(
    List<double> embedding, {
    double threshold = 1.2,
  }) async {
    final db = await database;
    final rows = await db.query('faces');
    LocalFaceMatch? best;
    for (final row in rows) {
      final stored = (jsonDecode(row['embedding'] as String) as List)
          .cast<num>()
          .map((e) => e.toDouble())
          .toList();
      final distance = euclideanDistance(embedding, stored);
      if (best == null || distance < best.distance) {
        best = LocalFaceMatch(
          userId: row['userId'] as String,
          name: (row['name'] ?? '').toString(),
          distance: distance,
        );
      }
    }
    if (best == null || best.distance > threshold) return null;
    return best;
  }

  Future<void> queueLog(AccessLog log) async {
    final db = await database;
    await db.insert('pending_logs', {
      'id': log.id,
      'payload': jsonEncode(
        log.toMap()..['timestamp'] = log.timestamp.toIso8601String(),
      ),
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> pendingLogs() async {
    final db = await database;
    return db.query('pending_logs', orderBy: 'createdAt ASC');
  }

  Future<void> deletePendingLog(String id) async {
    final db = await database;
    await db.delete('pending_logs', where: 'id = ?', whereArgs: [id]);
  }

  double euclideanDistance(List<double> a, List<double> b) {
    if (a.length != b.length) return double.infinity;
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return sum == 0 ? 0 : sum.sqrt();
  }
}

extension on double {
  double sqrt() {
    var x = this;
    var y = 1.0;
    for (var i = 0; i < 16; i++) {
      y = (y + x / y) / 2;
    }
    return y;
  }
}
