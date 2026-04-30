import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;

import '../models/access_log.dart';
import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/area.dart';
import '../models/system_settings.dart';

class FirebaseService {
  FirebaseService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  Stream<User?> authStateChanges() => auth.authStateChanges();

  Future<UserCredential> login(String email, String password) {
    return auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
    required String department,
    required String phone,
    required String room,
  }) async {
    final cred = await _authCall(
      () => auth.createUserWithEmailAndPassword(email: email.trim(), password: password),
    );
    final user = AppUser(
      id: cred.user!.uid,
      name: name.trim(),
      email: email.trim(),
      department: department.trim(),
      phone: phone.trim(),
      room: room.trim(),
      role: 'admin',
      createdAt: DateTime.now(),
      hasFace: false,
    );
    await userRef(user.id).set(user.toMap());
    return user;
  }

  Future<T> _authCall<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'configuration-not-found' ||
          e.message?.contains('CONFIGURATION_NOT_FOUND') == true) {
        throw Exception(
          'Firebase Auth is not configured for this app. Enable Email/Password sign-in in Firebase Authentication and make sure the Android app package is com.example.fazekey.',
        );
      }
      throw Exception(e.message ?? 'Firebase Auth failed: ${e.code}');
    }
  }

  DocumentReference<Map<String, dynamic>> userRef(String id) => firestore.collection('users').doc(id);

  Future<AppUser?> currentUserProfile() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return null;
    return getUser(uid);
  }

  Future<AppUser?> getUser(String id) async {
    final snap = await userRef(id).get();
    if (!snap.exists || snap.data() == null) return null;
    return AppUser.fromMap(snap.id, snap.data()!);
  }

  Future<void> saveFace(String userId, List<double> embedding) async {
    await userRef(userId).set({
      'hasFace': true,
      'faceEmbedding': embedding,
      'faceUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> signOut() => auth.signOut();

  Stream<List<Area>> watchAreas() => firestore
      .collection('areas')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => Area.fromMap(d.id, d.data())).toList());

  Future<void> addArea(Area area) => firestore.collection('areas').add(area.toMap());

  Future<void> updateArea(Area area) => firestore.collection('areas').doc(area.id).set(area.toMap(), SetOptions(merge: true));

  Future<void> updateAreaOccupancy(String areaId, int delta) async {
    if (areaId.isEmpty) return;
    await firestore.collection('areas').doc(areaId).set({
      'currentOccupancy': FieldValue.increment(delta),
    }, SetOptions(merge: true));
  }

  Stream<List<AccessLog>> watchLogs({String? query, int limit = 30}) {
    return firestore
        .collection('accessLogs')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) {
      final logs = s.docs.map((d) => AccessLog.fromMap(d.id, d.data())).toList();
      if (query == null || query.trim().isEmpty) return logs;
      final q = query.toLowerCase();
      return logs.where((l) => '${l.userName} ${l.areaName} ${l.status} ${l.reason}'.toLowerCase().contains(q)).toList();
    });
  }

  Future<void> addLog(AccessLog log) async {
    await firestore.collection('accessLogs').doc(log.id).set(log.toMap());
    if (log.granted) {
      await updateAreaOccupancy(log.areaId, 1);
    }
    await _maybeCreateSecurityNotification(log);
  }

  Future<void> syncEncodedLog(Map<String, dynamic> row) async {
    final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    payload['timestamp'] = Timestamp.fromDate(DateTime.parse(payload['timestamp'] as String));
    payload['synced'] = true;
    await firestore.collection('accessLogs').doc(row['id'] as String).set(payload);
  }

  Stream<List<AppNotification>> watchNotifications() => firestore
      .collection('notifications')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => AppNotification.fromMap(d.id, d.data())).toList());

  DocumentReference<Map<String, dynamic>> get systemSettingsRef => firestore.collection('system').doc('settings');

  Stream<SystemSettings> watchSystemSettings() {
    return systemSettingsRef.snapshots().map((s) => SystemSettings.fromMap(s.data()));
  }

  Future<void> saveSystemSettings(SystemSettings settings) {
    return systemSettingsRef.set(settings.toMap(), SetOptions(merge: true));
  }

  Future<SystemSettings> getSystemSettings() async {
    final snap = await systemSettingsRef.get();
    return SystemSettings.fromMap(snap.data());
  }

  Future<void> _maybeCreateSecurityNotification(AccessLog log) async {
    final settings = await getSystemSettings();
    if (!settings.afterHoursAlerts || !settings.isAfterHours) return;
    if (log.granted && !settings.globalLockdown) return;
    await firestore.collection('notifications').add({
      'title': log.isUnknownFace ? 'Unknown face after hours' : 'Access alert after hours',
      'body': '${log.userName} at ${log.areaName}: ${log.reason}',
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, int>> dashboardStats() async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final users = await firestore.collection('users').count().get();
    final areas = await firestore.collection('areas').count().get();
    final active = await firestore.collection('accessLogs').where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start)).where('status', isEqualTo: 'granted').count().get();
    final denied = await firestore.collection('accessLogs').where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start)).where('status', isEqualTo: 'denied').count().get();
    return {
      'activeToday': active.count ?? 0,
      'deniedAccess': denied.count ?? 0,
      'usersRegistered': users.count ?? 0,
      'areasMonitored': areas.count ?? 0,
    };
  }
}
