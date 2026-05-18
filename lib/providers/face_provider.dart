import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/access_log.dart';
import '../models/app_user.dart';
import '../models/area.dart';
import '../services/face_recognition_service.dart';
import '../services/firebase_service.dart';

class FaceProvider extends ChangeNotifier {
  FaceProvider(this._face, this._firebase);

  final FaceRecognitionService _face;
  final FirebaseService _firebase;
  bool loading = false;
  String? error;
  double? lastDistance;
  String? lastMatchedUserId;
  bool _disposed = false;

  Future<bool> ensureModelReady() async {
    loading = true;
    error = null;
    _notifyAfterFrame();
    try {
      await _face.initialize();
      loading = false;
      _notifyAfterFrame();
      return true;
    } catch (e) {
      error = e.toString();
      loading = false;
      _notifyAfterFrame();
      return false;
    }
  }

  Future<bool> registerFace(
    AppUser user,
    List<XFile> captures, {
    String? userId,
  }) async {
    loading = true;
    error = null;
    _notifyAfterFrame();
    try {
      final faceUserId = (userId ?? _firebase.currentUserId)?.trim();
      if (faceUserId == null || faceUserId.isEmpty) {
        throw Exception('A Firebase Auth UID is required for face enrollment.');
      }
      final embedding = await _face.averageEmbeddings(captures);
      await _firebase.saveFace(
        faceUserId,
        embedding,
        photoUrl: captures.first.path,
      );
      await _face.localDb.upsertFace(
        userId: faceUserId,
        name: user.name,
        embedding: embedding,
      );
      loading = false;
      _notifyAfterFrame();
      return true;
    } catch (e) {
      error = e.toString();
      loading = false;
      _notifyAfterFrame();
      return false;
    }
  }

  Future<AppUser?> identify(XFile capture) async {
    loading = true;
    error = null;
    lastMatchedUserId = null;
    _notifyAfterFrame();
    try {
      final match = await _face.identify(capture);
      lastDistance = match?.distance;
      lastMatchedUserId = match?.userId;
      final user = match == null ? null : await _firebase.getUser(match.userId);
      if (match != null && user == null) {
        error =
            'Face matched UID ${match.userId}, but no users/${match.userId} profile exists.';
      }
      loading = false;
      _notifyAfterFrame();
      return user;
    } catch (e) {
      error = e.toString();
      loading = false;
      _notifyAfterFrame();
      return null;
    }
  }

  Future<bool> validateLiveness(XFile capture) async {
    loading = true;
    error = null;
    _notifyAfterFrame();
    try {
      await _face.validateLiveness(capture);
      loading = false;
      _notifyAfterFrame();
      return true;
    } catch (e) {
      error = e.toString();
      loading = false;
      _notifyAfterFrame();
      return false;
    }
  }

  Future<void> closeDetector() => _face.closeDetector();

  AccessLog buildLog({
    required AppUser? user,
    Area? area,
    String areaId = '',
    String areaName = 'No active room configured',
    String? status,
    String? reason,
    String? snapshotPath,
  }) {
    final granted = status == null ? user != null : status == 'granted';
    return AccessLog(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      userId: user?.id ?? '',
      userName: user?.name ?? 'Unknown face',
      areaId: area?.id ?? areaId,
      areaName: area?.name ?? areaName,
      status: granted ? 'granted' : 'denied',
      reason: granted
          ? (reason ?? 'Face verified offline')
          : (reason ?? 'Face not recognized'),
      timestamp: DateTime.now(),
      synced: false,
      snapshotPath: snapshotPath,
    );
  }

  void _notifyAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      notifyListeners();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_face.close());
    super.dispose();
  }
}
