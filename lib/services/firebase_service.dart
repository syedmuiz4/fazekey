import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:url_launcher/url_launcher.dart';

import '../models/access_log.dart';
import '../models/access_grant.dart';
import '../models/app_user.dart';
import '../models/area.dart';
import '../models/incident_report.dart';
import '../models/system_settings.dart';

class FirebaseService {
  FirebaseService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : auth = auth ?? FirebaseAuth.instance,
      firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  Stream<User?> authStateChanges() => auth.authStateChanges();

  String? get currentUserId => auth.currentUser?.uid;

  String? get currentUserEmail => auth.currentUser?.email;

  Future<bool> validateAdminSession(String profileId) async {
    final account = auth.currentUser;
    if (account == null || account.uid != profileId) return false;
    final user = await getUser(profileId);
    return user?.isAdmin == true;
  }

  Future<UserCredential> login(String email, String password) {
    return auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
    required String department,
    required String phone,
    required String room,
    List<String> rooms = const [],
    String role = 'student',
    int accessLevel = 3,
    String identityNumber = '',
    String position = 'Student',
  }) async {
    final adminRole = _isAdminRole(role);
    final normalizedRole = adminRole ? 'Admin' : 'User';
    final normalizedPosition = adminRole
        ? 'Admin'
        : _normalizedPosition(position);
    final assignedRooms = adminRole
        ? const <String>[]
        : _normalizedRooms([...rooms, room]);
    final cred = await _authCall(
      () => auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
    );
    final user = AppUser(
      id: cred.user!.uid,
      name: name.trim(),
      email: email.trim(),
      department: department.trim(),
      phone: phone.trim(),
      room: _primaryRoom(assignedRooms),
      rooms: assignedRooms,
      role: normalizedRole,
      position: normalizedPosition,
      identityNumber: identityNumber.trim(),
      course: department.trim(),
      faculty: 'FSKTM',
      currentSemester: 'Semester 1',
      accessLevel: adminRole ? 3 : accessLevel.clamp(1, 3).toInt(),
      status: adminRole ? 'approved' : 'pending',
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
        throw Exception('Account recovery is not configured for this app.');
      }
      throw Exception(e.message ?? 'Authentication failed: ${e.code}');
    }
  }

  DocumentReference<Map<String, dynamic>> userRef(String id) =>
      firestore.collection('users').doc(id);

  Future<AppUser?> currentUserProfile() async {
    final account = auth.currentUser;
    if (account == null) return null;
    return await getUser(account.uid) ?? _fallbackUser(account);
  }

  Future<AppUser?> getUser(String id) async {
    final snap = await userRef(id).get();
    if (!snap.exists || snap.data() == null) return null;
    return AppUser.fromMap(snap.id, snap.data()!);
  }

  Future<AppUser?> getUserByEmail(String email) async {
    final target = email.trim();
    if (target.isEmpty) return null;
    final snap = await firestore
        .collection('users')
        .where('email', isEqualTo: target)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return AppUser.fromMap(doc.id, doc.data());
  }

  Stream<AppUser?> watchUser(String id) {
    return userRef(id).snapshots().map((snap) {
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      return AppUser.fromMap(snap.id, data);
    });
  }

  Stream<List<AppUser>> watchAllUsers() {
    return firestore
        .collection('users')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => AppUser.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Stream<AppUser?> watchCurrentUserProfile() {
    return authStateChanges().asyncExpand((user) {
      if (user == null) return Stream<AppUser?>.value(null);
      return userRef(user.uid).snapshots().map((snap) {
        final data = snap.data();
        if (snap.exists && data != null) return AppUser.fromMap(snap.id, data);
        return _fallbackUser(user);
      });
    });
  }

  Future<List<AppUser>> getAllUsers() async {
    final snap = await firestore
        .collection('users')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((doc) => AppUser.fromMap(doc.id, doc.data())).toList();
  }

  Future<void> updateUserProfile(AppUser user) {
    return userRef(user.id).set({
      'name': user.name.trim(),
      if (user.email.trim().isNotEmpty) 'email': user.email.trim(),
      'department': user.department.trim(),
      'phone': user.phone.trim(),
      'room': user.isAdmin ? '' : _primaryRoom(user.assignedRooms),
      'rooms': user.isAdmin ? const <String>[] : user.assignedRooms,
      'permittedZones': user.isAdmin ? const <String>[] : user.assignedRooms,
      'role': user.isAdmin ? 'Admin' : 'User',
      'position': user.isAdmin ? 'Admin' : _normalizedPosition(user.position),
      'identityNumber': user.identityNumber.trim(),
      'course': user.course.trim(),
      'faculty': user.faculty.trim(),
      'currentSemester': user.currentSemester.trim(),
      'accessLevel': user.accessLevel.clamp(1, 3),
      'status': user.status.trim().isEmpty ? 'approved' : user.status.trim(),
      'homeAddress': user.homeAddress.trim(),
      'emergencyContact': user.emergencyContact.trim(),
      'createdAt': Timestamp.fromDate(user.createdAt),
      'hasFace': user.hasFace,
      if (user.photoUrl?.trim().isNotEmpty == true) 'photoUrl': user.photoUrl,
      if (user.pendingPhotoUrl?.trim().isNotEmpty == true)
        'pendingPhotoUrl': user.pendingPhotoUrl,
      if (user.photoChangeRequestedAt != null)
        'photoChangeRequestedAt': Timestamp.fromDate(
          user.photoChangeRequestedAt!,
        ),
      if (user.photoUpdatedAt != null)
        'photoUpdatedAt': Timestamp.fromDate(user.photoUpdatedAt!),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<AppUser> createManagedUser({
    required String name,
    required String identityNumber,
    required String email,
    required String department,
    required String phone,
    required String room,
    List<String> rooms = const [],
    required String role,
    required int accessLevel,
    String course = '',
    String faculty = 'FSKTM',
    String position = 'Student',
  }) async {
    final adminRole = _isAdminRole(role);
    final normalizedRole = adminRole ? 'Admin' : 'User';
    final normalizedPosition = adminRole
        ? 'Admin'
        : _normalizedPosition(position);
    final assignedRooms = adminRole
        ? const <String>[]
        : _normalizedRooms([...rooms, room]);
    final ref = firestore.collection('users').doc();
    final user = AppUser(
      id: ref.id,
      name: name.trim(),
      email: email.trim(),
      department: department.trim(),
      phone: phone.trim(),
      room: _primaryRoom(assignedRooms),
      rooms: assignedRooms,
      role: normalizedRole,
      position: normalizedPosition,
      identityNumber: identityNumber.trim(),
      course: course.trim().isEmpty ? department.trim() : course.trim(),
      faculty: faculty.trim().isEmpty ? 'FSKTM' : faculty.trim(),
      currentSemester: 'Semester 1',
      accessLevel: adminRole ? 3 : accessLevel.clamp(1, 3).toInt(),
      status: adminRole ? 'approved' : 'pending',
      createdAt: DateTime.now(),
      hasFace: false,
    );
    await ref.set(user.toMap());
    return user;
  }

  Future<void> deleteManagedUser(String id) async => userRef(id).delete();

  Future<void> approveUserIdentity(String userId) {
    return userRef(userId).set({
      'status': 'approved',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  CollectionReference<Map<String, dynamic>> get accessGrantsRef =>
      firestore.collection('accessGrants');

  Stream<List<AccessGrant>> watchAccessGrants({
    String? userId,
    String? areaId,
    int limit = 120,
  }) async* {
    Query<Map<String, dynamic>> query = accessGrantsRef;
    if (userId?.trim().isNotEmpty == true) {
      query = query.where('userId', isEqualTo: userId!.trim());
    }
    if (areaId?.trim().isNotEmpty == true) {
      query = query.where('areaId', isEqualTo: areaId!.trim());
    }
    try {
      await for (final snap
          in query
              .orderBy('startAt', descending: true)
              .limit(limit)
              .snapshots()) {
        yield snap.docs
            .map((doc) => AccessGrant.fromMap(doc.id, doc.data()))
            .toList();
      }
    } catch (_) {
      yield const <AccessGrant>[];
    }
  }

  Future<List<AccessGrant>> getAccessGrantsForUser(String userId) async {
    final snap = await accessGrantsRef
        .where('userId', isEqualTo: userId.trim())
        .get();
    final grants =
        snap.docs.map((doc) => AccessGrant.fromMap(doc.id, doc.data())).toList()
          ..sort((a, b) => b.startAt.compareTo(a.startAt));
    return grants;
  }

  Future<void> grantRoomAccess({
    required AppUser user,
    required Area area,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    if (!endAt.isAfter(startAt)) {
      throw Exception('Access end date must be after the start date.');
    }
    final grant = AccessGrant(
      id: '',
      userId: user.id,
      userName: user.name.trim().isEmpty ? user.id : user.name.trim(),
      userPosition: user.roleLabel,
      areaId: area.id,
      areaName: _areaRoomLabel(area),
      startAt: startAt,
      endAt: endAt,
      active: true,
      createdAt: DateTime.now(),
    );
    await accessGrantsRef.add(grant.toMap());
    final assignedRooms = _normalizedRooms([
      ...user.assignedRooms,
      grant.areaName,
    ]);
    await userRef(user.id).set({
      'room': _primaryRoom(assignedRooms),
      'rooms': assignedRooms,
      'permittedZones': assignedRooms,
      'status': 'approved',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deactivateAccessGrant(String grantId) {
    return accessGrantsRef.doc(grantId).set({
      'active': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<AccessGrantEvaluation> evaluateAccessGrant({
    required AppUser user,
    required Area area,
    required DateTime moment,
  }) async {
    if (user.hasAdminOverride) {
      return AccessGrantEvaluation(
        granted: true,
        expired: false,
        grant: AccessGrant(
          id: 'admin_override',
          userId: user.id,
          userName: user.name,
          userPosition: user.roleLabel,
          areaId: area.id,
          areaName: _areaRoomLabel(area),
          startAt: DateTime(2000),
          endAt: DateTime(2100),
          active: true,
          createdAt: DateTime.now(),
        ),
      );
    }
    final snap = await accessGrantsRef
        .where('userId', isEqualTo: user.id)
        .where('areaId', isEqualTo: area.id)
        .get();
    final grants = snap.docs
        .map((doc) => AccessGrant.fromMap(doc.id, doc.data()))
        .where((grant) => grant.active)
        .toList();
    for (final grant in grants) {
      if (grant.isActiveAt(moment)) {
        return AccessGrantEvaluation(
          granted: true,
          expired: false,
          grant: grant,
        );
      }
    }
    final expired = grants.where((grant) => grant.isExpiredAt(moment)).toList()
      ..sort((a, b) => b.endAt.compareTo(a.endAt));
    if (expired.isNotEmpty) {
      return AccessGrantEvaluation(
        granted: false,
        expired: true,
        grant: expired.first,
      );
    }
    final pending =
        grants.where((grant) => grant.startsLaterThan(moment)).toList()
          ..sort((a, b) => a.startAt.compareTo(b.startAt));
    if (pending.isNotEmpty) {
      return AccessGrantEvaluation(
        granted: false,
        expired: false,
        grant: pending.first,
      );
    }
    return AccessGrantEvaluation.none;
  }

  Future<void> approveUserAccess({
    required String userId,
    required String room,
    required int accessLevel,
    List<String>? rooms,
  }) {
    final assignedRooms = _normalizedRooms([...?rooms, room]);
    return userRef(userId).set({
      'room': _primaryRoom(assignedRooms),
      'rooms': assignedRooms,
      'permittedZones': assignedRooms,
      'accessLevel': accessLevel.clamp(1, 3),
      'status': 'approved',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> revokeUserAccess(String userId) {
    return userRef(userId).set({
      'room': '',
      'rooms': const <String>[],
      'permittedZones': const <String>[],
      'status': 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> revokeUserFromArea({
    required String areaId,
    required String userId,
  }) {
    return firestore.collection('areas').doc(areaId).set({
      'revokedUserIds': FieldValue.arrayUnion([userId]),
      'allowedUserIds': FieldValue.arrayRemove([userId]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> restoreUserForArea({
    required String areaId,
    required String userId,
  }) {
    return firestore.collection('areas').doc(areaId).set({
      'revokedUserIds': FieldValue.arrayRemove([userId]),
      'allowedUserIds': FieldValue.arrayUnion([userId]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> requestProfilePhotoUpdate({
    required String userId,
    required String photoUrl,
  }) async {
    final profile = await getUser(userId);
    if (profile == null) throw Exception('User profile was not found.');
    final now = DateTime.now();
    final lastChange = profile.photoUpdatedAt ?? profile.photoChangeRequestedAt;
    if (lastChange != null &&
        lastChange.year == now.year &&
        lastChange.month == now.month) {
      throw Exception('Profile picture changes are limited to once per month.');
    }
    await userRef(userId).set({
      'pendingPhotoUrl': photoUrl.trim(),
      'photoChangeRequestedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> approveProfilePhotoUpdate(String userId) async {
    final profile = await getUser(userId);
    final pending = profile?.pendingPhotoUrl?.trim();
    if (pending == null || pending.isEmpty) {
      throw Exception('No pending profile picture request was found.');
    }
    await userRef(userId).set({
      'photoUrl': pending,
      'pendingPhotoUrl': FieldValue.delete(),
      'photoUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> rejectProfilePhotoUpdate(String userId) {
    return userRef(userId).set({
      'pendingPhotoUrl': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveFace(
    String userId,
    List<double> embedding, {
    String? photoUrl,
  }) async {
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

  Future<void> sendSetupEmail(String email, {AppUser? user}) async {
    final target = email.trim();
    if (target.isEmpty) {
      throw Exception('A registered email address is required.');
    }
    final profile = user ?? await getUserByEmail(target);
    final displayName = (profile?.name.trim().isNotEmpty == true)
        ? profile!.name.trim()
        : 'FAZEKEY user';
    final roleLabel = profile?.roleLabel ?? 'User';
    final room = profile?.room.trim();
    final roomLine = room == null || room.isEmpty
        ? 'Your assigned room will appear in your User ID after setup.'
        : 'Assigned room: $room';
    final credentialLines = [
      'Registered email: $target',
      if (profile?.identityNumber.trim().isNotEmpty == true)
        'User ID: ${profile!.identityNumber.trim()}',
      'Role: $roleLabel',
      roomLine,
    ].join('\r\n');
    final body =
        'Hello $displayName,\r\n\r\n'
        'Your $roleLabel User ID has been created in FAZEKEY.\r\n\r\n'
        '$credentialLines\r\n\r\n'
        'Open the app, sign in with your registered email, and complete Identity Enrollment to activate Face Identity access. Your verified face scan will grant access only to your pre-registered room under FAZEKEY RBAC policy.\r\n\r\n'
        'Regards,\r\n'
        'FAZEKEY Credentialing Services';
    final uri = Uri(
      scheme: 'mailto',
      path: target,
      queryParameters: {'subject': 'FAZEKEY Access Enrollment', 'body': body},
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) throw Exception('Unable to open a local email application.');
  }

  Stream<List<Area>> watchAreas() => firestore
      .collection('areas')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => Area.fromMap(d.id, d.data())).toList());

  Future<void> addArea(Area area) =>
      firestore.collection('areas').add(area.toMap());

  Future<void> deleteArea(String id) =>
      firestore.collection('areas').doc(id).delete();

  Future<void> ensureSampleAreas() async {
    for (final entry in _sampleAreas.entries) {
      final ref = firestore.collection('areas').doc(entry.key);
      final snap = await ref.get();
      if (!snap.exists) {
        await ref.set(entry.value.toMap());
      }
    }
  }

  Future<void> updateArea(Area area) async {
    final areaRef = firestore.collection('areas').doc(area.id);
    final existing = await areaRef.get();
    final previous = existing.exists && existing.data() != null
        ? Area.fromMap(existing.id, existing.data()!)
        : null;
    final oldRoomLabel = previous == null ? '' : _areaRoomLabel(previous);
    final newRoomLabel = _areaRoomLabel(area);
    final batch = firestore.batch()
      ..set(areaRef, area.toMap(), SetOptions(merge: true));

    if (previous != null &&
        oldRoomLabel.trim().isNotEmpty &&
        newRoomLabel.trim().isNotEmpty &&
        oldRoomLabel.trim() != newRoomLabel.trim()) {
      final oldRoomKeys = _areaRoomKeys(previous);
      final users = await firestore.collection('users').get();
      for (final doc in users.docs) {
        final user = AppUser.fromMap(doc.id, doc.data());
        if (!user.assignedRooms.any(
          (room) => oldRoomKeys.contains(_accessKey(room)),
        )) {
          continue;
        }
        final updatedRooms = user.assignedRooms
            .map(
              (room) => oldRoomKeys.contains(_accessKey(room))
                  ? newRoomLabel.trim()
                  : room,
            )
            .toSet()
            .toList();
        batch.set(doc.reference, {
          'room': _primaryRoom(updatedRooms),
          'rooms': updatedRooms,
          'permittedZones': updatedRooms,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    await batch.commit();
  }

  Future<void> updateAreaOccupancy(String areaId, int delta) async {
    if (areaId.isEmpty) return;
    await firestore.collection('areas').doc(areaId).set({
      'currentOccupancy': FieldValue.increment(delta),
    }, SetOptions(merge: true));
  }

  Stream<List<AccessLog>> watchLogs({String? query, int limit = 30}) async* {
    try {
      await for (final s
          in firestore
              .collection('accessLogs')
              .orderBy('timestamp', descending: true)
              .limit(limit)
              .snapshots()) {
        final logs = s.docs
            .map((d) => AccessLog.fromMap(d.id, d.data()))
            .toList();
        if (query == null || query.trim().isEmpty) {
          yield logs;
          continue;
        }
        final q = query.toLowerCase();
        yield logs
            .where(
              (l) => '${l.userName} ${l.areaName} ${l.status} ${l.reason}'
                  .toLowerCase()
                  .contains(q),
            )
            .toList();
      }
    } catch (_) {
      yield const <AccessLog>[];
    }
  }

  Stream<List<AccessLog>> watchUserLogs(
    String userId, {
    int limit = 30,
  }) async* {
    try {
      await for (final s
          in firestore
              .collection('accessLogs')
              .where('userId', isEqualTo: userId)
              .limit(limit)
              .snapshots()) {
        final logs =
            s.docs.map((d) => AccessLog.fromMap(d.id, d.data())).toList()
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        yield logs;
      }
    } catch (_) {
      yield const <AccessLog>[];
    }
  }

  Future<List<AccessLog>> getUserLogs(
    String userId, {
    DateTime? start,
    DateTime? end,
  }) async {
    final snap = await firestore
        .collection('accessLogs')
        .where('userId', isEqualTo: userId)
        .get();
    return _filterAndSortLogs(
      snap.docs.map((doc) => AccessLog.fromMap(doc.id, doc.data())),
      start: start,
      end: end,
    );
  }

  Future<List<AccessLog>> getRoomLogs({
    String? areaId,
    String? areaName,
    DateTime? start,
    DateTime? end,
  }) async {
    final collection = firestore.collection('accessLogs');
    final snap = areaId?.trim().isNotEmpty == true
        ? await collection.where('areaId', isEqualTo: areaId!.trim()).get()
        : await collection.get();
    final roomName = areaName?.trim().toLowerCase();
    final logs = snap.docs
        .map((doc) => AccessLog.fromMap(doc.id, doc.data()))
        .where(
          (log) =>
              roomName == null ||
              roomName.isEmpty ||
              log.areaName.trim().toLowerCase() == roomName,
        );
    return _filterAndSortLogs(logs, start: start, end: end);
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
    String reporterIdentityNumber = '',
    String lastScannedLocation = '',
  }) async {
    final report = {
      'reporterId': reporterId,
      'reporterName': reporterName.trim(),
      'reporterIdentityNumber': reporterIdentityNumber.trim(),
      'title': title.trim(),
      'severity': severity.trim(),
      'areaName': areaName.trim(),
      'lastScannedLocation': lastScannedLocation.trim().isEmpty
          ? areaName.trim()
          : lastScannedLocation.trim(),
      'details': details.trim(),
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    };
    await firestore.collection('incidentReports').add(report);
  }

  Stream<List<IncidentReport>> watchIncidentReports({int limit = 40}) {
    return firestore
        .collection('incidentReports')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => IncidentReport.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> syncEncodedLog(Map<String, dynamic> row) async {
    final payload =
        jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    payload['timestamp'] = Timestamp.fromDate(
      DateTime.parse(payload['timestamp'] as String),
    );
    payload['synced'] = true;
    await firestore
        .collection('accessLogs')
        .doc(row['id'] as String)
        .set(payload);
  }

  DocumentReference<Map<String, dynamic>> get systemSettingsRef =>
      firestore.collection('system').doc('system_config');

  Stream<SystemSettings> watchSystemSettings() {
    return systemSettingsRef.snapshots().map(
      (s) => SystemSettings.fromMap(s.data()),
    );
  }

  Future<void> saveSystemSettings(SystemSettings settings) {
    return systemSettingsRef.set(settings.toMap(), SetOptions(merge: true));
  }

  Future<void> activateEmergencyLockdown({String source = 'dashboard_sos'}) {
    return systemSettingsRef.set({
      'globalLockdown': true,
      'system_status': 'lockdown',
      'lockdownSource': source,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
    final active = await firestore
        .collection('accessLogs')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('status', isEqualTo: 'granted')
        .count()
        .get();
    final denied = await firestore
        .collection('accessLogs')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('status', isEqualTo: 'denied')
        .count()
        .get();
    return {
      'activeToday': active.count ?? 0,
      'deniedAccess': denied.count ?? 0,
      'usersRegistered': users.count ?? 0,
      'areasMonitored': areas.count ?? 0,
    };
  }

  static bool _isAdminRole(String role) => role.trim().toLowerCase() == 'admin';

  static List<AccessLog> _filterAndSortLogs(
    Iterable<AccessLog> logs, {
    DateTime? start,
    DateTime? end,
  }) {
    final filtered = logs.where((log) {
      if (start != null && log.timestamp.isBefore(start)) return false;
      if (end != null && !log.timestamp.isBefore(end)) return false;
      return true;
    }).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return filtered;
  }

  static List<String> _normalizedRooms(Iterable<String> values) {
    final rooms = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      if (rooms.any((room) => _accessKey(room) == _accessKey(trimmed))) {
        continue;
      }
      rooms.add(trimmed);
    }
    return rooms;
  }

  static String _primaryRoom(Iterable<String> values) {
    final rooms = _normalizedRooms(values);
    return rooms.isEmpty ? '' : rooms.first;
  }

  static String _normalizedPosition(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'staff') return 'Staff';
    return 'Student';
  }

  static String _accessKey(String value) =>
      value.trim().toLowerCase().replaceAll(' ', '');

  static String _areaRoomLabel(Area area) {
    final name = area.name.trim();
    if (name.isNotEmpty) return name;
    final floor = area.floor.trim();
    final roomNumber = area.roomNumber.trim();
    if (floor.isNotEmpty && roomNumber.isNotEmpty) {
      return '$floor - Room $roomNumber';
    }
    if (roomNumber.isNotEmpty) return 'Room $roomNumber';
    return area.location.trim();
  }

  static Set<String> _areaRoomKeys(Area area) {
    final floor = area.floor.trim();
    final roomNumber = area.roomNumber.trim();
    final location = area.location.trim();
    final floorRoom = floor.isNotEmpty && roomNumber.isNotEmpty
        ? '$floor - Room $roomNumber'
        : '';
    final locationFloorRoom = location.isNotEmpty && floorRoom.isNotEmpty
        ? '$location - $floorRoom'
        : '';
    return {
      area.name,
      area.roomNumber,
      if (roomNumber.isNotEmpty) 'Room $roomNumber',
      floorRoom,
      locationFloorRoom,
      _areaRoomLabel(area),
    }.map(_accessKey).where((value) => value.isNotEmpty).toSet();
  }

  AppUser _fallbackUser(User user) => AppUser(
    id: user.uid,
    name: user.displayName ?? '',
    email: user.email ?? '',
    department: '',
    phone: user.phoneNumber ?? '',
    room: '',
    role: 'User',
    position: 'Student',
    identityNumber: user.uid,
    course: '',
    faculty: 'FSKTM',
    currentSemester: '',
    accessLevel: 3,
    status: 'approved',
    createdAt: DateTime.now(),
    hasFace: false,
  );

  static final Map<String, Area> _sampleAreas = {
    'sample_level_1_access_lab': Area(
      id: 'sample_level_1_access_lab',
      name: 'Level 1 - Access Lab',
      location: 'FSKTM',
      floor: 'Level 1',
      roomNumber: '31',
      active: true,
      createdAt: DateTime(2026),
      allowedDepartments: const [
        'Software Engineering',
        'Information Security',
      ],
      allowedRoles: const ['User', 'Admin'],
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
      allowedRoles: const ['User', 'Admin'],
      currentOccupancy: 0,
      capacity: 25,
    ),
    'sample_level_3_it_room': Area(
      id: 'sample_level_3_it_room',
      name: 'IT Room',
      location: 'FSKTM',
      floor: 'Level 3',
      roomNumber: '33',
      active: true,
      createdAt: DateTime(2026, 1, 3),
      allowedDepartments: const ['Information Security'],
      allowedRoles: const ['Admin', 'User'],
      currentOccupancy: 0,
      capacity: 10,
    ),
  };
}
