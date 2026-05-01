import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;

import '../models/access_log.dart';
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

  Future<void> updateUserProfile(AppUser user) {
    return userRef(user.id).set(user.toMap(), SetOptions(merge: true));
  }

  Future<void> saveFace(String userId, List<double> embedding, {String? photoUrl}) async {
    await userRef(userId).set({
      'hasFace': true,
      'faceEmbedding': embedding,
      'photoUrl': ?photoUrl,
      'faceUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> signOut() => auth.signOut();

  Future<void> sendPasswordResetEmail(String email) {
    return _authCall(() => auth.sendPasswordResetEmail(email: email.trim()));
  }

  Stream<List<Area>> watchAreas() => firestore
      .collection('areas')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => Area.fromMap(d.id, d.data())).toList());

  Future<void> addArea(Area area) => firestore.collection('areas').add(area.toMap());

  Future<void> ensureSampleAreas() async {
    for (final entry in _sampleAreas.entries) {
      final ref = firestore.collection('areas').doc(entry.key);
      final snap = await ref.get();
      if (!snap.exists) {
        await ref.set(entry.value.toMap());
      }
    }
  }

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
  }

  Future<void> addIncidentReport({
    required String reporterId,
    required String reporterName,
    required String title,
    required String severity,
    required String areaName,
    required String details,
  }) async {
    final report = {
      'reporterId': reporterId,
      'reporterName': reporterName.trim(),
      'title': title.trim(),
      'severity': severity.trim(),
      'areaName': areaName.trim(),
      'details': details.trim(),
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    };
    await firestore.collection('incidentReports').add(report);
  }

  Future<void> syncEncodedLog(Map<String, dynamic> row) async {
    final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    payload['timestamp'] = Timestamp.fromDate(DateTime.parse(payload['timestamp'] as String));
    payload['synced'] = true;
    await firestore.collection('accessLogs').doc(row['id'] as String).set(payload);
  }

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

  static final Map<String, Area> _sampleAreas = {
    'sample_level_1_access_lab': Area(
      id: 'sample_level_1_access_lab',
      name: 'Level 1 - Access Lab',
      location: 'FSKTM',
      floor: 'Level 1',
      roomNumber: '31',
      active: true,
      createdAt: DateTime(2026),
      allowedDepartments: const ['Software Engineering', 'Information Security'],
      allowedRoles: const ['Admin', 'Security', 'Staff'],
      currentOccupancy: 0,
      capacity: 25,
    ),
    'sample_level_2_research_suite': Area(
      id: 'sample_level_2_research_suite',
      name: 'Level 2 - Research Suite',
      location: 'FSKTM',
      floor: 'Level 2',
      roomNumber: '32',
      active: true,
      createdAt: DateTime(2026, 1, 2),
      allowedDepartments: const ['Multimedia', 'Information Security'],
      allowedRoles: const ['Admin', 'Security', 'Staff'],
      currentOccupancy: 0,
      capacity: 25,
    ),
  };
}
