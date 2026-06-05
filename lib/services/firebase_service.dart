import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:firebase_core/firebase_core.dart';
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

  CollectionReference<Map<String, dynamic>> get userNotificationsRef =>
      firestore.collection('userNotifications');

  CollectionReference<Map<String, dynamic>> get adminNotificationsRef =>
      firestore.collection('adminNotifications');

  Future<void> _notifyUser({
    required String userId,
    required String title,
    required String message,
    String type = 'request',
  }) {
    final target = userId.trim();
    if (target.isEmpty) return Future.value();
    return userNotificationsRef.add({
      'userId': target,
      'title': title.trim(),
      'message': message.trim(),
      'type': type.trim(),
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _notifyAdmins({
    required String title,
    required String message,
    String type = 'request',
    String relatedId = '',
  }) {
    final cleanTitle = title.trim();
    final cleanMessage = message.trim();
    if (cleanTitle.isEmpty && cleanMessage.isEmpty) return Future.value();
    return adminNotificationsRef.add({
      'title': cleanTitle,
      'message': cleanMessage,
      'type': type.trim(),
      'relatedId': relatedId.trim(),
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchUserNotifications(
    String userId, {
    int limit = 20,
  }) {
    return userNotificationsRef
        .where('userId', isEqualTo: userId.trim())
        .limit(limit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchUnreadAdminNotifications({
    int limit = 99,
  }) {
    return adminNotificationsRef
        .where('read', isEqualTo: false)
        .limit(limit)
        .snapshots();
  }

  Future<void> markAdminNotificationsRead() async {
    final snap = await adminNotificationsRef
        .where('read', isEqualTo: false)
        .limit(400)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = firestore.batch();
    for (final doc in snap.docs) {
      batch.set(doc.reference, {
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> markUserNotificationsRead(String userId) async {
    final target = userId.trim();
    if (target.isEmpty) return;
    final snap = await userNotificationsRef
        .where('userId', isEqualTo: target)
        .where('read', isEqualTo: false)
        .limit(200)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = firestore.batch();
    for (final doc in snap.docs) {
      batch.set(doc.reference, {
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

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

  bool isTemporaryPasswordExpired(AppUser user, {DateTime? now}) {
    if (!user.requiresPasswordChange) return false;
    final expiresAt = user.temporaryPasswordExpiresAt;
    if (expiresAt == null) return false;
    return !(now ?? DateTime.now()).isBefore(expiresAt);
  }

  Future<void> updateCurrentAccountPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final account = auth.currentUser;
    final email = account?.email?.trim();
    final cleanCurrentPassword = currentPassword.trim();
    final cleanNewPassword = newPassword.trim();
    if (account == null || email == null || email.isEmpty) {
      throw Exception('No signed-in account is available.');
    }
    if (cleanCurrentPassword.isEmpty || cleanNewPassword.length < 6) {
      throw Exception(
        'Current password and a 6+ character new password are required.',
      );
    }
    await _reauthenticateCurrentAccount(
      email: email,
      password: cleanCurrentPassword,
    );
    await _authCall(() => account.updatePassword(cleanNewPassword));
  }

  Future<void> completeTemporaryPasswordChange({
    required String currentPassword,
    required String newPassword,
  }) async {
    final account = auth.currentUser;
    final email = account?.email?.trim();
    final cleanCurrentPassword = currentPassword.trim();
    final cleanNewPassword = newPassword.trim();
    if (account == null || email == null || email.isEmpty) {
      throw Exception('No signed-in account is available.');
    }
    if (cleanCurrentPassword.isEmpty) {
      throw Exception('Current temporary password is required.');
    }
    _validateStrongTemporaryPassword(cleanNewPassword);
    if (cleanCurrentPassword == cleanNewPassword) {
      throw Exception(
        'Choose a new password that is different from the temporary password.',
      );
    }
    final profile = await getUser(account.uid);
    if (profile != null && isTemporaryPasswordExpired(profile)) {
      throw Exception(
        'Temporary password expired. Ask admin to send the temporary password again.',
      );
    }
    try {
      await _reauthenticateCurrentAccount(
        email: email,
        password: cleanCurrentPassword,
      );
    } on FirebaseAuthException {
      throw Exception(
        'Temporary password is incorrect or expired. Ask admin to send the temporary password again.',
      );
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('credential') ||
          message.contains('password') ||
          message.contains('expired')) {
        throw Exception(
          'Temporary password is incorrect or expired. Ask admin to send the temporary password again.',
        );
      }
      rethrow;
    }
    await _authCall(() => account.updatePassword(cleanNewPassword));
    await userRef(account.uid).set({
      'requiresPasswordChange': false,
      'temporaryPasswordExpiresAt': FieldValue.delete(),
      'temporaryPasswordChangedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> updateCurrentAccountEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    final account = auth.currentUser;
    final email = account?.email?.trim();
    final cleanCurrentPassword = currentPassword.trim();
    final cleanNewEmail = newEmail.trim();
    if (account == null || email == null || email.isEmpty) {
      throw Exception('No signed-in admin account is available.');
    }
    if (cleanCurrentPassword.isEmpty || cleanNewEmail.isEmpty) {
      throw Exception('Current password and a new email are required.');
    }
    await _reauthenticateCurrentAccount(
      email: email,
      password: cleanCurrentPassword,
    );
    var updatedImmediately = false;
    try {
      // ignore: deprecated_member_use
      await _authCall(() => account.updateEmail(cleanNewEmail));
      await account.reload();
      updatedImmediately =
          auth.currentUser?.email?.trim().toLowerCase() ==
          cleanNewEmail.toLowerCase();
    } catch (_) {
      await _authCall(() => account.verifyBeforeUpdateEmail(cleanNewEmail));
    }
    await systemSettingsRef.set({
      'administratorEmail': cleanNewEmail,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await userRef(account.uid).set({
      if (updatedImmediately) 'email': cleanNewEmail,
      if (updatedImmediately) 'pendingEmail': FieldValue.delete(),
      if (!updatedImmediately) 'pendingEmail': cleanNewEmail,
      if (!updatedImmediately) 'emailUpdateVerificationSent': true,
      if (!updatedImmediately)
        'emailUpdateVerificationSentAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return updatedImmediately;
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
      accessLevel: adminRole ? 3 : accessLevel.clamp(0, 3).toInt(),
      status: 'approved',
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

  Future<void> _reauthenticateCurrentAccount({
    required String email,
    required String password,
  }) {
    final account = auth.currentUser;
    if (account == null) {
      throw Exception('No signed-in account is available.');
    }
    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    return _authCall(() => account.reauthenticateWithCredential(credential));
  }

  Future<String> _createManagedAuthUser({
    required String email,
    required String password,
  }) async {
    final secondaryAppName =
        'fazekey-managed-user-${DateTime.now().microsecondsSinceEpoch}';
    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: secondaryAppName,
        options: Firebase.app().options,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final credential = await _authCall(
        () => secondaryAuth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        ),
      );
      final uid = credential.user?.uid;
      if (uid == null || uid.trim().isEmpty) {
        throw Exception('Unable to create the user login account.');
      }
      await secondaryAuth.signOut();
      return uid;
    } finally {
      await secondaryApp?.delete();
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
      'accessLevel': user.accessLevel.clamp(0, 3),
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
    required String temporaryPassword,
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
    final cleanEmail = email.trim();
    final cleanTemporaryPassword = temporaryPassword.trim();
    if (cleanEmail.isEmpty) {
      throw Exception('A registered email address is required.');
    }
    if (cleanTemporaryPassword.isEmpty) {
      throw Exception('A temporary password is required.');
    }
    late final String authUid;
    try {
      authUid = await _createManagedAuthUser(
        email: cleanEmail,
        password: cleanTemporaryPassword,
      );
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('email') && message.contains('already')) {
        throw Exception(
          'This email still exists in Firebase Authentication: $cleanEmail. '
          'Delete that Authentication user in Firebase Console, then register again.',
        );
      }
      rethrow;
    }
    final ref = userRef(authUid);
    final user = AppUser(
      id: ref.id,
      name: name.trim(),
      email: cleanEmail,
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
      accessLevel: adminRole ? 3 : accessLevel.clamp(0, 3).toInt(),
      status: adminRole ? 'approved' : 'pending',
      createdAt: DateTime.now(),
      hasFace: false,
    );
    final issuedAt = DateTime.now();
    await ref.set({
      ...user.toMap(),
      'authUid': authUid,
      'temporaryPasswordIssuedAt': Timestamp.fromDate(issuedAt),
      'temporaryPasswordExpiresAt': Timestamp.fromDate(
        issuedAt.add(const Duration(hours: 1)),
      ),
      'temporaryPasswordEmailSent': false,
      'requiresPasswordChange': true,
    });
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
    final batch = firestore.batch();
    await _deactivateActiveRoomGrantsForUserInBatch(
      batch,
      user.id,
      exceptAreaId: area.id,
      removeAreaAccess: true,
    );
    batch.set(accessGrantsRef.doc(), grant.toMap());
    _setUserSingleRoomAccessInBatch(
      batch,
      userId: user.id,
      area: area,
      areaName: grant.areaName,
      extraUserFields: {if (approveUser) 'status': 'approved'},
    );
    if (area.id.trim().isNotEmpty) {
      batch.set(firestore.collection('areas').doc(area.id), {
        'allowedUserIds': FieldValue.arrayUnion([user.id]),
        'revokedUserIds': FieldValue.arrayRemove([user.id]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
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
    DateTime? accessValidFrom,
    DateTime? accessValidUntil,
  }) {
    final assignedRooms = _normalizedRooms([...?rooms, room]);
    return userRef(userId).set({
      'room': _primaryRoom(assignedRooms),
      'rooms': assignedRooms,
      'permittedZones': assignedRooms,
      'accessLevel': accessLevel.clamp(0, 3),
      'status': 'approved',
      if (accessValidFrom != null)
        'accessValidFrom': Timestamp.fromDate(accessValidFrom),
      if (accessValidUntil != null)
        'accessValidUntil': Timestamp.fromDate(accessValidUntil),
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
    final existing = await firestore
        .collection('profilePhotoRequests')
        .where('userId', isEqualTo: userId.trim())
        .where('status', isEqualTo: 'open')
        .limit(1)
        .get();
    final payload = {
      'userId': profile.id,
      'userName': profile.name.trim().isEmpty ? profile.id : profile.name,
      'email': profile.email,
      'photoUrl': photoUrl.trim(),
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (existing.docs.isEmpty) {
      final ref = await firestore
          .collection('profilePhotoRequests')
          .add(payload);
      await _notifyAdmins(
        title: 'Profile picture request',
        message: '${payload['userName']} requested a new profile picture.',
        type: 'profilePhoto',
        relatedId: ref.id,
      );
    } else {
      await existing.docs.first.reference.set(payload, SetOptions(merge: true));
      await _notifyAdmins(
        title: 'Profile picture request updated',
        message: '${payload['userName']} updated a profile picture request.',
        type: 'profilePhoto',
        relatedId: existing.docs.first.id,
      );
    }
  }

  Future<void> requestProfileUpdate({
    required AppUser current,
    required AppUser requested,
  }) async {
    final ref = await firestore.collection('profileChangeRequests').add({
      'userId': current.id,
      'userName': current.name.trim().isEmpty ? current.id : current.name,
      'email': current.email,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'current': {
        'name': current.name,
        'department': current.department,
        'course': current.course,
        'phone': current.phone,
        'homeAddress': current.homeAddress,
        'emergencyContact': current.emergencyContact,
      },
      'requested': {
        'name': requested.name.trim(),
        'department': requested.department.trim(),
        'course': requested.course.trim(),
        'phone': requested.phone.trim(),
        'homeAddress': requested.homeAddress.trim(),
        'emergencyContact': requested.emergencyContact.trim(),
      },
    });
    await _notifyAdmins(
      title: 'Profile change request',
      message:
          '${current.name.trim().isEmpty ? current.id : current.name} requested profile changes.',
      type: 'profile',
      relatedId: ref.id,
    );
  }

  Future<void> decideProfileChangeRequest({
    required String requestId,
    required String userId,
    required bool approved,
    required Map<String, dynamic> requested,
  }) async {
    final id = requestId.trim();
    final target = userId.trim();
    if (id.isEmpty || target.isEmpty) return;
    if (approved) {
      await userRef(target).set({
        'name': (requested['name'] ?? '').toString().trim(),
        'department': (requested['department'] ?? '').toString().trim(),
        'course': (requested['course'] ?? '').toString().trim(),
        'phone': (requested['phone'] ?? '').toString().trim(),
        'homeAddress': (requested['homeAddress'] ?? '').toString().trim(),
        'emergencyContact': (requested['emergencyContact'] ?? '')
            .toString()
            .trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await firestore.collection('profileChangeRequests').doc(id).set({
      'status': approved ? 'approved' : 'denied',
      'decidedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _notifyUser(
      userId: target,
      title: 'Profile change ${approved ? 'approved' : 'denied'}',
      message: approved
          ? 'Your profile change request has been approved by admin.'
          : 'Your profile change request was not approved by admin.',
      type: 'profile',
    );
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
    await _notifyUser(
      userId: userId,
      title: 'Profile photo approved',
      message: 'Your profile photo change has been approved by admin.',
      type: 'profile',
    );
  }

  Future<void> rejectProfilePhotoUpdate(String userId) async {
    await userRef(userId).set({
      'pendingPhotoUrl': FieldValue.delete(),
      'photoChangeRequestedAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _notifyUser(
      userId: userId,
      title: 'Profile photo denied',
      message: 'Your profile photo change was not approved by admin.',
      type: 'profile',
    );
  }

  Future<void> decideProfilePhotoRequest({
    required String requestId,
    required String userId,
    required bool approved,
  }) async {
    final id = requestId.trim();
    final target = userId.trim();
    if (id.isEmpty || target.isEmpty) return;
    if (approved) {
      await approveProfilePhotoUpdate(target);
    } else {
      await rejectProfilePhotoUpdate(target);
    }
    await firestore.collection('profilePhotoRequests').doc(id).set({
      'status': approved ? 'approved' : 'denied',
      'decidedAt': FieldValue.serverTimestamp(),
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
      if (photoUrl?.trim().isNotEmpty == true) 'photoUrl': photoUrl!.trim(),
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
    final ref = await roomAccessRequestsRef.add(request.toMap());
    await _notifyAdmins(
      title: 'Room access request',
      message: '${request.userName} requested access to ${request.areaName}.',
      type: 'room',
      relatedId: ref.id,
    );
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
      await _activateApprovedRoomRequest(
        user: user,
        area: area,
        areaName: request.areaName.trim().isEmpty
            ? _areaRoomLabel(area)
            : request.areaName,
      );
    }
    await roomAccessRequestsRef.doc(request.id).set({
      'status': allowed ? 'allowed' : 'denied',
      'decidedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _notifyUser(
      userId: request.userId,
      title: 'Room request ${allowed ? 'approved' : 'denied'}',
      message: allowed
          ? 'Your request to enter ${request.areaName} has been approved by admin.'
          : 'Your request to enter ${request.areaName} was not approved by admin.',
      type: 'room',
    );
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

  Stream<List<RoomAccessRecord>> watchUserRoomAccessRecords(
    String userId, {
    int limit = 200,
  }) {
    final id = userId.trim();
    if (id.isEmpty) return Stream.value(const <RoomAccessRecord>[]);
    return roomAccessRecordsRef
        .where('userId', isEqualTo: id)
        .limit(limit)
        .snapshots()
        .map(
          (snap) =>
              snap.docs
                  .map((doc) => RoomAccessRecord.fromMap(doc.id, doc.data()))
                  .toList()
                ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
        );
  }

  Stream<List<RoomAccessRecord>> watchActiveRoomSessions() {
    return activeRoomSessionsRef.snapshots().map(
      (snap) => snap.docs
          .map((doc) => RoomAccessRecord.fromMap(doc.id, doc.data()))
          .toList(),
    );
  }

  Stream<RoomAccessRecord?> watchActiveRoomSession(String userId) {
    final id = userId.trim();
    if (id.isEmpty) return Stream.value(null);
    return activeRoomSessionsRef.doc(id).snapshots().map((snap) {
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      return RoomAccessRecord.fromMap(snap.id, data);
    });
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
    await _deactivateActiveRoomGrantsForUserInBatch(
      batch,
      user.id,
      exceptAreaId: area.id,
      removeAreaAccess: true,
    );
    _setUserSingleRoomAccessInBatch(
      batch,
      userId: user.id,
      area: area,
      areaName: areaName,
    );
    if (area.id.trim().isNotEmpty) {
      batch.set(firestore.collection('areas').doc(area.id), {
        'allowedUserIds': FieldValue.arrayUnion([user.id]),
        'revokedUserIds': FieldValue.arrayRemove([user.id]),
        'currentOccupancy': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
    return const RoomSessionChange(allowed: true);
  }

  Future<void> _activateApprovedRoomRequest({
    required AppUser user,
    required Area area,
    required String areaName,
  }) async {
    final active = await getActiveRoomSession(user.id);
    if (active != null && active.areaId == area.id) return;
    final now = DateTime.now();
    final sessionId = '${user.id}_${now.microsecondsSinceEpoch}';
    final entry = RoomAccessRecord(
      id: sessionId,
      sessionId: sessionId,
      userId: user.id,
      userName: user.name.trim().isEmpty ? user.id : user.name.trim(),
      areaId: area.id,
      areaName: areaName,
      event: 'entry',
      timestamp: now,
      reason: 'Admin-approved room request',
    );
    final batch = firestore.batch();
    if (active != null) {
      final exit = RoomAccessRecord(
        id: '${active.sessionId}_switch_${now.microsecondsSinceEpoch}',
        sessionId: active.sessionId,
        userId: active.userId,
        userName: active.userName,
        areaId: active.areaId,
        areaName: active.areaName,
        event: 'exit',
        timestamp: now,
        reason: 'Switched by approved room request',
      );
      batch.set(roomAccessRecordsRef.doc(exit.id), exit.toMap());
      if (active.areaId.trim().isNotEmpty) {
        batch.set(
          firestore.collection('areas').doc(active.areaId),
          {
            'allowedUserIds': FieldValue.arrayRemove([user.id]),
            'currentOccupancy': FieldValue.increment(-1),
          },
          SetOptions(merge: true),
        );
      }
    }
    batch.set(roomAccessRecordsRef.doc(entry.id), entry.toMap());
    batch.set(activeRoomSessionsRef.doc(user.id), entry.toMap());
    await _deactivateActiveRoomGrantsForUserInBatch(
      batch,
      user.id,
      exceptAreaId: area.id,
    );
    _setUserSingleRoomAccessInBatch(
      batch,
      userId: user.id,
      area: area,
      areaName: areaName,
    );
    if (area.id.trim().isNotEmpty) {
      batch.set(firestore.collection('areas').doc(area.id), {
        'allowedUserIds': FieldValue.arrayUnion([user.id]),
        'revokedUserIds': FieldValue.arrayRemove([user.id]),
        'currentOccupancy': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
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
    await _deactivateActiveRoomGrantsForUserInBatch(batch, user.id);
    _clearUserRoomAccessInBatch(batch, userId: user.id);
    if (area.id.trim().isNotEmpty) {
      batch.set(firestore.collection('areas').doc(area.id), {
        'allowedUserIds': FieldValue.arrayRemove([user.id]),
        'currentOccupancy': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
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
    await _deactivateActiveRoomGrantsForUserInBatch(batch, user.id);
    _clearUserRoomAccessInBatch(batch, userId: user.id);
    if (active.areaId.trim().isNotEmpty) {
      batch.set(firestore.collection('areas').doc(active.areaId), {
        'allowedUserIds': FieldValue.arrayRemove([user.id]),
        'currentOccupancy': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
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
    await _authCall(() => auth.sendPasswordResetEmail(email: target));
    final ref = await firestore.collection('passwordResetRequests').add({
      'userId': user?.id ?? '',
      'userName': displayName,
      'email': target,
      'status': 'open',
      'emailSent': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _notifyUser(
      userId: user?.id ?? '',
      title: 'Password reset email sent',
      message: 'Please check your email for the Fazekey password reset link.',
      type: 'password',
    );
    await _notifyAdmins(
      title: 'Password reset request',
      message: '$displayName requested password help for $target.',
      type: 'password',
      relatedId: ref.id,
    );
  }

  Future<void> sendTemporaryPasswordSetupEmail(AppUser user) async {
    final target = user.email.trim();
    if (target.isEmpty) {
      throw Exception('A registered email address is required.');
    }
    await _authCall(() => auth.sendPasswordResetEmail(email: target));
    try {
      await userRef(user.id).set({
        'requiresPasswordChange': false,
        'temporaryPasswordExpiresAt': FieldValue.delete(),
        'temporaryPasswordSetupEmailSent': true,
        'temporaryPasswordSetupEmailSentAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // The Firebase email was already sent; profile metadata is best-effort.
    }
    try {
      await _notifyUser(
        userId: user.id,
        title: 'Temporary password email sent',
        message:
            'Please check your email and follow the secure password setup link.',
        type: 'password',
      );
    } catch (_) {
      // Notification writes should not make the direct email action fail.
    }
  }

  Future<void> decidePasswordResetRequest({
    required String requestId,
    required String userId,
    required bool approved,
  }) async {
    final id = requestId.trim();
    if (id.isEmpty) return;
    await firestore.collection('passwordResetRequests').doc(id).set({
      'status': approved ? 'approved' : 'denied',
      'decidedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _notifyUser(
      userId: userId,
      title: 'Password request ${approved ? 'approved' : 'denied'}',
      message: approved
          ? 'Your password reset request has been approved by admin. Please check your email.'
          : 'Your password reset request was not approved by admin.',
      type: 'password',
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
        ? 'syedmuizzuddin03@gmail.com'
        : settings.administratorEmail.trim();
    final ref = await firestore.collection('supportRequests').add({
      'userId': user.id,
      'userName': user.name,
      'email': user.email,
      'contact': cleanContact,
      'subject': cleanSubject,
      'message': cleanMessage,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _notifyAdmins(
      title: 'Support request',
      message:
          '${user.name.trim().isEmpty ? user.id : user.name} requested help: $cleanSubject.',
      type: 'support',
      relatedId: ref.id,
    );
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
    required String temporaryPassword,
  }) async {
    final target = email.trim();
    if (target.isEmpty) {
      throw Exception('A registered email address is required.');
    }
    final cleanTemporaryPassword = temporaryPassword.trim();
    if (cleanTemporaryPassword.isEmpty) {
      throw Exception('A temporary password is required.');
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
      'Temporary password: $cleanTemporaryPassword',
      if (profile?.identityNumber.trim().isNotEmpty == true)
        'User ID: ${profile!.identityNumber.trim()}',
      'Role: $roleLabel',
      roomLine,
    ].join('\r\n');
    final body =
        'Your Fazekey access is live, $displayName. Use the temporary password below to unlock your first door.\r\n\r\n'
        'Important: change this password after your first sign-in.\r\n\r\n'
        '$credentialLines\r\n\r\n'
        'Next steps:\r\n'
        '1. Open FAZEKEY and sign in with the registered email and temporary password.\r\n'
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
    if (profile != null) {
      final issuedAt = DateTime.now();
      await userRef(profile.id).set({
        'requiresPasswordChange': true,
        'temporaryPasswordIssuedAt': Timestamp.fromDate(issuedAt),
        'temporaryPasswordExpiresAt': Timestamp.fromDate(
          issuedAt.add(const Duration(hours: 1)),
        ),
        'temporaryPasswordEmailSent': true,
        'temporaryPasswordEmailSentAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
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
    final batch = firestore.batch();
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

  void _setUserSingleRoomAccessInBatch(
    WriteBatch batch, {
    required String userId,
    required Area area,
    required String areaName,
    Map<String, Object?> extraUserFields = const {},
  }) {
    final roomLabel = _normalizedRooms([
      areaName.trim().isEmpty ? _areaRoomLabel(area) : areaName,
    ]);
    batch.set(userRef(userId), {
      'room': _primaryRoom(roomLabel),
      'rooms': roomLabel,
      'permittedZones': roomLabel,
      ...extraUserFields,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _clearUserRoomAccessInBatch(WriteBatch batch, {required String userId}) {
    batch.set(userRef(userId), {
      'room': '',
      'rooms': const <String>[],
      'permittedZones': const <String>[],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _deactivateActiveRoomGrantsForUserInBatch(
    WriteBatch batch,
    String userId, {
    String? exceptAreaId,
    bool removeAreaAccess = false,
  }) async {
    final cleanUserId = userId.trim();
    if (cleanUserId.isEmpty) return;
    final snap = await accessGrantsRef
        .where('userId', isEqualTo: cleanUserId)
        .where('active', isEqualTo: true)
        .get();
    final keepAreaId = exceptAreaId?.trim();
    final cleanedAreaIds = <String>{};
    for (final doc in snap.docs) {
      final grantAreaId = (doc.data()['areaId'] as String? ?? '').trim();
      if (keepAreaId != null &&
          keepAreaId.isNotEmpty &&
          grantAreaId == keepAreaId) {
        continue;
      }
      batch.set(doc.reference, {
        'active': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (removeAreaAccess &&
          grantAreaId.isNotEmpty &&
          cleanedAreaIds.add(grantAreaId)) {
        batch.set(firestore.collection('areas').doc(grantAreaId), {
          'allowedUserIds': FieldValue.arrayRemove([cleanUserId]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
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
    final ref = await firestore.collection('incidentReports').add(report);
    await _notifyAdmins(
      title: 'Incident report',
      message:
          '${reporterName.trim().isEmpty ? reporterId : reporterName.trim()} submitted an incident report.',
      type: 'incident',
      relatedId: ref.id,
    );
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

  static void _validateStrongTemporaryPassword(String password) {
    if (password.length < 12) {
      throw Exception('New password must be at least 12 characters long.');
    }
    if (!RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      throw Exception(
        'New password must include uppercase and lowercase letters, numbers, and symbols.',
      );
    }
  }

  static String _accessKey(String value) =>
      value.trim().toLowerCase().replaceAll(' ', '');

  static String _areaRoomLabel(Area area) {
    final name = area.name.trim();
    final roomNumber = area.roomNumber.trim();
    if (name.isNotEmpty) return name;
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
      area.id,
      area.name,
      area.roomNumber,
      if (floor.isNotEmpty && area.name.trim().isNotEmpty)
        '$floor - ${area.name}',
      if (location.isNotEmpty && area.name.trim().isNotEmpty)
        '$location - ${area.name}',
      if (location.isNotEmpty &&
          floor.isNotEmpty &&
          area.name.trim().isNotEmpty)
        '$location - $floor - ${area.name}',
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
