import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/access_log.dart';
import '../services/firebase_service.dart';
import '../services/local_database_service.dart';

class LogProvider extends ChangeNotifier {
  LogProvider(this._firebase, this._localDb);

  final FirebaseService _firebase;
  final LocalDatabaseService _localDb;
  StreamSubscription<List<AccessLog>>? _sub;
  List<AccessLog> logs = [];
  String query = '';
  int limit = 30;
  bool loading = false;
  bool syncing = false;
  int pendingCount = 0;
  DateTime? lastSyncedAt;
  String? error;

  void listen() {
    _sub?.cancel();
    _sub = _firebase
        .watchLogs(query: query, limit: limit)
        .listen(
          (value) {
            logs = value;
            notifyListeners();
          },
          onError: (e) {
            error = e.toString();
            notifyListeners();
          },
        );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    logs = [];
    error = null;
    notifyListeners();
  }

  void search(String value) {
    query = value;
    listen();
  }

  void loadMore() {
    limit += 30;
    listen();
  }

  Future<void> record(AccessLog log, {bool firestoreLogging = true}) async {
    if (!firestoreLogging) return;
    try {
      await _firebase.addLog(log);
    } catch (e) {
      await _localDb.queueLog(log);
      pendingCount = (await _localDb.pendingLogs()).length;
      notifyListeners();
      if (_isPermissionDenied(e)) rethrow;
      return;
    }
    notifyListeners();
  }

  bool _isPermissionDenied(Object error) =>
      (error is FirebaseException &&
          error.plugin == 'cloud_firestore' &&
          error.code == 'permission-denied') ||
      error.toString().toLowerCase().contains(
        'cloud_firestore/permission-denied',
      );

  Future<void> syncPending() async {
    syncing = true;
    error = null;
    pendingCount = (await _localDb.pendingLogs()).length;
    notifyListeners();
    final rows = await _localDb.pendingLogs();
    for (final row in rows) {
      try {
        await _firebase.syncEncodedLog(row);
        await _localDb.deletePendingLog(row['id'] as String);
      } catch (e) {
        error = 'Offline log sync paused: $e';
        break;
      }
    }
    pendingCount = (await _localDb.pendingLogs()).length;
    lastSyncedAt = DateTime.now();
    syncing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
