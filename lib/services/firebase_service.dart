import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:url_launcher/url_launcher.dart';

import '../constants/command_center_options.dart';
import '../models/access_log.dart';
import '../models/access_grant.dart';
import '../models/app_user.dart';
import '../models/area.dart';
import '../models/incident_report.dart';
import '../models/room_access_record.dart';
import '../models/room_access_request.dart';
import '../models/system_settings.dart';
import 'local_database_service.dart';

class RoomSessionChange {
  const RoomSessionChange({
    required this.allowed,
    this.activeSession,
    this.message = '',
  });

  final bool allowed;
  final RoomAccessRecord? activeSession;
  final String message;
}

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

  Future<void> deleteManagedUser(String id) async {
    final userId = id.trim();
    if (userId.isEmpty) return;
    final grants = await accessGrantsRef
        .where('userId', isEqualTo: userId)
        .get();
    final areas = await firestore.collection('areas').get();
    final batch = firestore.batch()
      ..delete(userRef(userId))
      ..delete(activeRoomSessionsRef.doc(userId));
    for (final grant in grants.docs) {
      batch.delete(grant.reference);
    }
    for (final area in areas.docs) {
      batch.set(area.reference, {
        'allowedUserIds': FieldValue.arrayRemove([userId]),
        'revokedUserIds': FieldValue.arrayRemove([userId]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

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
    bool approveUser = true,
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
      if (approveUser) 'status': 'approved',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> revokeUserRoomAssignment({
    required AppUser user,
    required Area area,
  }) async {
    final roomKeys = {
      area.id,
      ..._areaRoomKeys(area),
    }.where((value) => value.trim().isNotEmpty).map(_accessKey).toSet();
    final remainingRooms = user.assignedRooms
        .where((room) => !roomKeys.contains(_accessKey(room)))
        .toList();

    final grants = await accessGrantsRef
        .where('userId', isEqualTo: user.id)
        .where('areaId', isEqualTo: area.id)
        .get();
    final batch = firestore.batch();
    batch.set(userRef(user.id), {
      'room': _primaryRoom(remainingRooms),
      'rooms': remainingRooms,
      'permittedZones': remainingRooms,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    for (final doc in grants.docs) {
      batch.set(doc.reference, {
        'active': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
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

  Future<void> revokeUserAccess(String userId) async {
    await userRef(userId).set({
      'room': '',
      'rooms': const <String>[],
      'permittedZones': const <String>[],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await activeRoomSessionsRef.doc(userId.trim()).delete().catchError((_) {});
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
      'biometricUid': userId,
      'status': 'approved',
      'photoUrl': ?photoUrl,
      'faceUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<LocalFaceMatch?> findNearestRemoteFace(
    List<double> embedding, {
    double threshold = 1.2,
  }) async {
    final snap = await firestore
        .collection('users')
        .where('hasFace', isEqualTo: true)
        .get();
    LocalFaceMatch? best;
    for (final doc in snap.docs) {
      final data = doc.data();
      final raw = data['faceEmbedding'];
      if (raw is! Iterable) continue;
      final stored = raw
          .map((value) => value is num ? value.toDouble() : null)
          .whereType<double>()
          .toList(growable: false);
      if (stored.length != embedding.length) continue;
      final distance = _euclideanDistance(embedding, stored);
      if (best == null || distance < best.distance) {
        best = LocalFaceMatch(
          userId: doc.id,
          name: (data['name'] ?? '').toString(),
          distance: distance,
        );
      }
    }
    if (best == null || best.distance > threshold) return null;
    return best;
  }

  Future<AppUser?> resolveBiometricUser(String biometricUid) async {
    final uid = biometricUid.trim();
    if (uid.isEmpty) return null;
    final direct = await getUser(uid);
    if (direct != null) return direct;

    for (final field in const [
      'biometricUid',
      'authUid',
      'uid',
      'faceUserId',
      'identityNumber',
    ]) {
      final snap = await firestore
          .collection('users')
          .where(field, isEqualTo: uid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final doc = snap.docs.first;
        await doc.reference.set({
          'biometricUid': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return AppUser.fromMap(doc.id, doc.data());
      }
    }

    final account = auth.currentUser;
    final email = account?.email?.trim();
    if (account?.uid == uid && email != null && email.isNotEmpty) {
      final byEmail = await getUserByEmail(email);
      if (byEmail != null) {
        await userRef(byEmail.id).set({
          'biometricUid': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return byEmail;
      }
    }
    return null;
  }

  Future<void> syncBiometricUid({
    required String userId,
    required String biometricUid,
  }) {
    final profileId = userId.trim();
    final uid = biometricUid.trim();
    if (profileId.isEmpty || uid.isEmpty) return Future.value();
    return userRef(profileId).set({
      'biometricUid': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> recordAppLogin(AppUser user, {String method = 'password'}) {
    return firestore.collection('appAuthRecords').add({
      'userId': user.id,
      'userName': user.name.trim().isEmpty ? user.id : user.name.trim(),
      'email': user.email.trim(),
      'event': 'login',
      'method': method,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordAppLogout(AppUser user, {String method = 'app'}) {
    return firestore.collection('appAuthRecords').add({
      'userId': user.id,
      'userName': user.name.trim().isEmpty ? user.id : user.name.trim(),
      'email': user.email.trim(),
      'event': 'logout',
      'method': method,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  CollectionReference<Map<String, dynamic>> get roomAccessRecordsRef =>
      firestore.collection('roomAccessRecords');

  CollectionReference<Map<String, dynamic>> get activeRoomSessionsRef =>
      firestore.collection('activeRoomSessions');

  CollectionReference<Map<String, dynamic>> get roomAccessRequestsRef =>
      firestore.collection('roomAccessRequests');

  Stream<List<RoomAccessRequest>> watchRoomAccessRequests() {
    return roomAccessRequestsRef
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => RoomAccessRequest.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> createRoomAccessRequest({
    required AppUser user,
    required Area area,
    required String areaName,
  }) async {
    final existing = await roomAccessRequestsRef
        .where('userId', isEqualTo: user.id)
        .where('areaId', isEqualTo: area.id)
        .where('status', isEqualTo: 'open')
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return;
    final request = RoomAccessRequest(
      id: '',
      userId: user.id,
      userName: user.name.trim().isEmpty ? user.id : user.name.trim(),
      areaId: area.id,
      areaName: areaName,
      status: 'open',
      createdAt: DateTime.now(),
    );
    await roomAccessRequestsRef.add(request.toMap());
  }

  Future<void> decideRoomAccessRequest({
    required RoomAccessRequest request,
    required bool allowed,
    Duration duration = const Duration(hours: 8),
  }) async {
    final user = await getUser(request.userId);
    final areaSnap = await firestore
        .collection('areas')
        .doc(request.areaId)
        .get();
    final areaData = areaSnap.data();
    final area = areaData == null
        ? commandCenterAreas[request.areaId]
        : Area.fromMap(areaSnap.id, areaData);
    if (allowed && user != null && area != null) {
      final now = DateTime.now();
      await grantRoomAccess(
        user: user,
        area: area,
        startAt: now,
        endAt: now.add(duration),
      );
    }
    await roomAccessRequestsRef.doc(request.id).set({
      'status': allowed ? 'allowed' : 'denied',
      'decidedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> cancelRoomAccessRequest(String requestId) {
    final id = requestId.trim();
    if (id.isEmpty) return Future.value();
    return roomAccessRequestsRef.doc(id).set({
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<RoomAccessRecord>> watchRoomAccessRecords({int limit = 500}) {
    return roomAccessRecordsRef
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => RoomAccessRecord.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Stream<List<RoomAccessRecord>> watchActiveRoomSessions() {
    return activeRoomSessionsRef.snapshots().map(
      (snap) => snap.docs
          .map((doc) => RoomAccessRecord.fromMap(doc.id, doc.data()))
          .toList(),
    );
  }

  Future<RoomAccessRecord?> getActiveRoomSession(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return null;
    final snap = await activeRoomSessionsRef.doc(id).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return RoomAccessRecord.fromMap(snap.id, data);
  }

  Future<RoomSessionChange> recordRoomEntry({
    required AppUser user,
    required Area area,
    required String areaName,
  }) async {
    final active = await getActiveRoomSession(user.id);
    if (active != null) {
      return RoomSessionChange(
        allowed: false,
        activeSession: active,
        message: 'Locked: Current session active elsewhere',
      );
    }
    final now = DateTime.now();
    final sessionId = '${user.id}_${now.microsecondsSinceEpoch}';
    final record = RoomAccessRecord(
      id: sessionId,
      sessionId: sessionId,
      userId: user.id,
      userName: user.name.trim().isEmpty ? user.id : user.name.trim(),
      areaId: area.id,
      areaName: areaName,
      event: 'entry',
      timestamp: now,
      reason: 'Biometric entry verified',
    );
    final batch = firestore.batch();
    batch.set(roomAccessRecordsRef.doc(record.id), record.toMap());
    batch.set(activeRoomSessionsRef.doc(user.id), record.toMap());
    if (area.id.trim().isNotEmpty) {
      batch.set(firestore.collection('areas').doc(area.id), {
        'currentOccupancy': FieldValue.increment(1),
      }, SetOptions(merge: true));
    }
    await batch.commit();
    return const RoomSessionChange(allowed: true);
  }

  Future<RoomSessionChange> recordRoomExit({
    required AppUser user,
    required Area area,
    required String areaName,
    String reason = 'Biometric exit verified',
  }) async {
    final active = await getActiveRoomSession(user.id);
    if (active == null) {
      return const RoomSessionChange(
        allowed: false,
        message: 'No active room session found',
      );
    }
    if (active.areaId != area.id) {
      return RoomSessionChange(
        allowed: false,
        activeSession: active,
        message: 'Locked: Current session active elsewhere',
      );
    }
    final now = DateTime.now();
    final recordId = '${active.sessionId}_exit_${now.microsecondsSinceEpoch}';
    final record = RoomAccessRecord(
      id: recordId,
      sessionId: active.sessionId,
      userId: user.id,
      userName: user.name.trim().isEmpty ? user.id : user.name.trim(),
      areaId: area.id,
      areaName: areaName,
      event: 'exit',
      timestamp: now,
      reason: reason,
    );
    final batch = firestore.batch();
    batch.set(roomAccessRecordsRef.doc(record.id), record.toMap());
    batch.delete(activeRoomSessionsRef.doc(user.id));
    if (area.id.trim().isNotEmpty) {
      batch.set(firestore.collection('areas').doc(area.id), {
        'currentOccupancy': FieldValue.increment(-1),
      }, SetOptions(merge: true));
    }
    await batch.commit();
    return const RoomSessionChange(allowed: true);
  }

  Future<void> closeActiveRoomSessionForUser(AppUser user) async {
    final active = await getActiveRoomSession(user.id);
    if (active == null) return;
    final now = DateTime.now();
    final record = RoomAccessRecord(
      id: '${active.sessionId}_logout_${now.microsecondsSinceEpoch}',
      sessionId: active.sessionId,
      userId: user.id,
      userName: user.name.trim().isEmpty ? user.id : user.name.trim(),
      areaId: active.areaId,
      areaName: active.areaName,
      event: 'exit',
      timestamp: now,
      reason: 'Application logout closed active room session',
    );
    final batch = firestore.batch();
    batch.set(roomAccessRecordsRef.doc(record.id), record.toMap());
    batch.delete(activeRoomSessionsRef.doc(user.id));
    if (active.areaId.trim().isNotEmpty) {
      batch.set(firestore.collection('areas').doc(active.areaId), {
        'currentOccupancy': FieldValue.increment(-1),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> signOut() => auth.signOut();

  Future<void> sendPasswordResetEmail(String email) async {
    final target = email.trim();
    if (target.isEmpty) {
      throw Exception('A registered email address is required.');
    }
    final user = await getUserByEmail(target);
    final displayName = user?.name.trim().isNotEmpty == true
        ? user!.name.trim()
        : '[User Name]';
    const resetUrl = 'https://fazekey.com/reset-password?token=xyz123';
    await firestore.collection('passwordResetRequests').add({
      'userId': user?.id ?? '',
      'userName': displayName,
      'email': target,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
    final body =
        '🔐 FAZEKEY PASSWORD RESET\r\n\r\n'
        'Hi $displayName,\r\n\r\n'
        'We received a request to reset your Fazekey password.\r\n\r\n'
        '                 🔒 RESET PASSWORD\r\n\r\n'
        'Or copy this link:\r\n'
        '$resetUrl\r\n\r\n'
        'This link will expire in 1 hour.\r\n\r\n'
        'If you didn\'t request this, please ignore this email.\r\n\r\n'
        '----------------------------------------\r\n'
        'Thanks,\r\n'
        '**Fazekey Security Team**\r\n\r\n'
        '⚠️ Never share this email with anyone.';
    await _launchMailto(
      target,
      subject: 'FAZEKEY Password Reset',
      body: body,
      requireOpened: false,
    );
  }

  Future<void> createSupportRequest({
    required AppUser user,
    required String subject,
    required String message,
    required String contact,
  }) async {
    final cleanSubject = subject.trim();
    final cleanMessage = message.trim();
    final cleanContact = contact.trim();
    if (cleanSubject.isEmpty || cleanMessage.isEmpty || cleanContact.isEmpty) {
      throw Exception('Subject, message, and contact are required.');
    }
    final settings = await getSystemSettings();
    final adminEmail = settings.administratorEmail.trim().isEmpty
        ? 'administrator@campus-access.local'
        : settings.administratorEmail.trim();
    await firestore.collection('supportRequests').add({
      'userId': user.id,
      'userName': user.name,
      'email': user.email,
      'contact': cleanContact,
      'subject': cleanSubject,
      'message': cleanMessage,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
    final body =
        'FAZEKEY HELP & SUPPORT\r\n\r\n'
        'User: ${user.name}\r\n'
        'Email: ${user.email}\r\n'
        'Contact: $cleanContact\r\n\r\n'
        'Subject: $cleanSubject\r\n\r\n'
        '$cleanMessage';
    await _launchMailto(
      adminEmail,
      subject: 'FAZEKEY Support Request - $cleanSubject',
      body: body,
      requireOpened: false,
    );
  }

  Future<void> sendSetupEmail(
    String email, {
    AppUser? user,
    String temporaryPassword = 'fx_9A3k7W',
  }) async {
    final target = email.trim();
    if (target.isEmpty) {
      throw Exception('A registered email address is required.');
    }
    final profile = user ?? await getUserByEmail(target);
    final displayName = (profile?.name.trim().isNotEmpty == true)
        ? profile!.name.trim()
        : 'FAZEKEY user';
    final roleLabel = profile?.roleLabel ?? 'User';
    final rooms = profile?.assignedRooms ?? const <String>[];
    final roomLine = rooms.isEmpty
        ? 'Authorized zones: Pending assignment'
        : 'Authorized zones: ${rooms.join(', ')}';
    final credentialLines = [
      'Registered email: $target',
      'Temporary password: $temporaryPassword',
      if (profile?.identityNumber.trim().isNotEmpty == true)
        'User ID: ${profile!.identityNumber.trim()}',
      'Role: $roleLabel',
      roomLine,
    ].join('\r\n');
    final body =
        'Your Fazekey access is live, $displayName. Use the temporary password below to unlock your first door.\r\n\r\n'
        'âš ï¸ This password expires in 24 hours.\r\n\r\n'
        '$credentialLines\r\n\r\n'
        'Next steps:\r\n'
        '1. Open FAZEKEY and sign in with the registered email.\r\n'
        '2. Complete Face Registration when prompted by the administrator.\r\n'
        '3. Access is limited to the authorized zones listed above.\r\n\r\n'
        'If you did not expect this account, contact your FAZEKEY administrator before signing in.\r\n\r\n'
        'Regards,\r\n'
        'FAZEKEY Security Operations';
    final opened = await _launchMailto(
      target,
      subject: 'FAZEKEY Security Portal Credentials',
      body: body,
    );
    if (!opened) throw Exception('Unable to open a local email application.');
  }

  Future<bool> _launchMailto(
    String email, {
    required String subject,
    required String body,
    bool requireOpened = true,
  }) async {
    final uri = Uri.parse(
      'mailto:${Uri.encodeComponent(email)}'
      '?subject=${Uri.encodeComponent(subject)}'
      '&body=${Uri.encodeComponent(body)}',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (requireOpened && !opened) {
      throw Exception('Unable to open a local email application.');
    }
    return opened;
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
    final allowedIds = commandCenterAreas.keys.toSet();
    final snap = await firestore.collection('areas').get();
    final batch = firestore.batch();
    for (final doc in snap.docs) {
      if (!allowedIds.contains(doc.id)) {
        batch.delete(doc.reference);
      }
    }
    for (final entry in commandCenterAreas.entries) {
      batch.set(
        firestore.collection('areas').doc(entry.key),
        entry.value.toMap(),
        SetOptions(merge: true),
      );
    }
    await batch.commit();
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

  static double _euclideanDistance(List<double> a, List<double> b) {
    if (a.length != b.length) return double.infinity;
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return math.sqrt(sum);
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
}
