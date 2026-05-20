import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/access_log.dart';
import '../models/app_user.dart';
import '../models/area.dart';
import '../services/face_recognition_service.dart';
import '../services/firebase_service.dart';
import '../services/local_database_service.dart';

class FaceProvider extends ChangeNotifier {
  FaceProvider(this._face, this._firebase);

  static const _verificationThreshold = .95;

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
    final match = await identifyLocalMatch(capture);
    return resolveLocalMatch(match);
  }

  Future<LocalFaceMatch?> identifyLocalMatch(XFile capture) async {
    loading = true;
    error = null;
    lastMatchedUserId = null;
    _notifyAfterFrame();
    try {
      final embedding = await _face.embeddingFromFile(capture);
      var match = await _face.localDb.findNearestFace(
        embedding,
        threshold: _verificationThreshold,
      );
      match ??= await _firebase.findNearestRemoteFace(
        embedding,
        threshold: _verificationThreshold,
      );
      lastDistance = match?.distance;
      lastMatchedUserId = match?.userId;
      loading = false;
      _notifyAfterFrame();
      return match;
    } catch (e) {
      error = e.toString();
      loading = false;
      _notifyAfterFrame();
      return null;
    }
  }

  Future<AppUser?> resolveLocalMatch(LocalFaceMatch? match) async {
    loading = true;
    error = null;
    _notifyAfterFrame();
    try {
      lastDistance = match?.distance;
      lastMatchedUserId = match?.userId;
      final user = match == null
          ? null
          : await _firebase.resolveBiometricUser(match.userId);
      if (match != null && user == null) {
        error =
            'Face matched UID ${match.userId}, but no users/${match.userId} profile exists.';
      }
      if (match != null && user != null && user.id != match.userId) {
        await _face.localDb.rekeyFace(
          fromUserId: match.userId,
          toUserId: user.id,
          name: user.name,
        );
        lastMatchedUserId = user.id;
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

  Future<bool> syncBiometricUid(AppUser user) async {
    loading = true;
    error = null;
    _notifyAfterFrame();
    try {
      final targetId = user.id.trim();
      final accountId = _firebase.currentUserId?.trim();
      if (targetId.isEmpty) {
        throw Exception('A Firestore user document is required for sync.');
      }
      if (accountId != null && accountId.isNotEmpty && accountId != targetId) {
        await _face.localDb.rekeyFace(
          fromUserId: accountId,
          toUserId: targetId,
          name: user.name,
        );
      }
      await _firebase.syncBiometricUid(
        userId: targetId,
        biometricUid: targetId,
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

  Future<void> deleteLocalFace(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    await _face.localDb.deleteFace(id);
    if (lastMatchedUserId == id) {
      lastMatchedUserId = null;
      lastDistance = null;
      _notifyAfterFrame();
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
    final normalizedStatus = status ?? (granted ? 'granted' : 'denied');
    return AccessLog(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      userId: user?.id ?? '',
      userName: user?.name ?? 'Unknown face',
      areaId: area?.id ?? areaId,
      areaName: area?.name ?? areaName,
      status: normalizedStatus,
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
