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

  Future<bool> ensureModelReady() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _face.initialize();
      loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> registerFace(AppUser user, List<XFile> captures) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final embedding = await _face.averageEmbeddings(captures);
      await _firebase.saveFace(user.id, embedding);
      await _face.localDb.upsertFace(userId: user.id, name: user.name, embedding: embedding);
      loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<AppUser?> identify(XFile capture) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final match = await _face.identify(capture);
      lastDistance = match?.distance;
      final user = match == null ? null : await _firebase.getUser(match.userId);
      loading = false;
      notifyListeners();
      return user;
    } catch (e) {
      error = e.toString();
      loading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> validateLiveness(XFile capture) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _face.validateLiveness(capture);
      loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      loading = false;
      notifyListeners();
      return false;
    }
  }

  AccessLog buildLog({
    required AppUser? user,
    Area? area,
    String areaId = '',
    String areaName = 'Campus Gate',
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
      reason: granted ? (reason ?? 'Face verified offline') : (reason ?? 'Face not recognized'),
      timestamp: DateTime.now(),
      synced: false,
      snapshotPath: snapshotPath,
    );
  }

  @override
  void dispose() {
    unawaited(_face.close());
    super.dispose();
  }
}
