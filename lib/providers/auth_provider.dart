import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/firebase_service.dart';
import '../services/local_database_service.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._firebase, this._localDb);

  final FirebaseService _firebase;
  final LocalDatabaseService _localDb;
  StreamSubscription<AppUser?>? _profileSub;
  AppUser? user;
  bool loading = true;
  bool darkMode = false;
  String? error;
  bool adminEmailUpdatePendingVerification = false;

  bool get isAuthenticated => user != null;

  bool get isAdmin => user?.isAdmin == true;

  bool get isUser => isAuthenticated && !isAdmin;

  bool get requiresPasswordChange =>
      user?.requiresPasswordChange == true && !isAdmin;

  bool get hasSignedInAccount => _firebase.currentUserId != null;

  String? get signedInAccountId => _firebase.currentUserId;

  String? get passwordResetEmail {
    final accountEmail = _firebase.currentUserEmail?.trim();
    if (accountEmail != null && accountEmail.isNotEmpty) return accountEmail;
    final profileEmail = user?.email.trim();
    if (profileEmail != null && profileEmail.isNotEmpty) return profileEmail;
    return null;
  }

  Future<void> bootstrap() async {
    _firebase.authStateChanges().listen((firebaseUser) async {
      await _profileSub?.cancel();
      _profileSub = null;
      user = null;
      loading = false;
      notifyListeners();
      if (firebaseUser == null) return;
      loading = true;
      notifyListeners();
      _profileSub = _firebase
          .watchUser(firebaseUser.uid)
          .listen(
            (profile) {
              user = profile;
              loading = false;
              notifyListeners();
            },
            onError: (e) {
              error = e.toString();
              loading = false;
              notifyListeners();
            },
          );
    });
    await _localDb.database;
  }

  Future<bool> login(String email, String password) async {
    return _guard(() async {
      final cred = await _firebase.login(email, password);
      user = await _firebase.getUser(cred.user!.uid);
      final profile = user;
      if (profile != null) {
        if (_firebase.isTemporaryPasswordExpired(profile)) {
          await _firebase.signOut();
          user = null;
          throw Exception(
            'Temporary password expired. Ask admin to send the temporary password again.',
          );
        }
        unawaited(_firebase.recordAppLogin(profile).catchError((_) {}));
      }
    });
  }

  Future<bool> register({
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
    return _guard(() async {
      user = await _firebase.register(
        name: name,
        email: email,
        password: password,
        department: department,
        phone: phone,
        room: room,
        rooms: rooms,
        role: role,
        accessLevel: accessLevel,
        identityNumber: identityNumber,
        position: position,
      );
    });
  }

  Future<bool> logout() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final profile = user;
      if (profile != null) {
        try {
          await _firebase.closeActiveRoomSessionForUser(profile);
          await _firebase.recordAppLogout(profile);
        } catch (_) {
          // Authentication sign-out should still complete if audit sync is delayed.
        }
      }
      await _firebase.signOut();
      user = null;
      return true;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void toggleDarkMode(bool value) {
    darkMode = value;
    notifyListeners();
  }

  Future<bool> refreshProfile() async {
    return _guard(() async {
      user = await _firebase.currentUserProfile();
    });
  }

  void completeFaceLogin(AppUser verifiedUser) {
    user = verifiedUser;
    loading = false;
    error = null;
    notifyListeners();
  }

  void syncProfileSnapshot(AppUser? latest) {
    if (_sameProfile(user, latest)) return;
    user = latest;
    loading = false;
    error = null;
    notifyListeners();
  }

  Stream<AppUser?> watchActiveUserProfile() {
    if (hasSignedInAccount) return _firebase.watchCurrentUserProfile();
    final activeUser = user;
    if (activeUser != null) return Stream<AppUser?>.value(activeUser);
    return Stream<AppUser?>.value(null);
  }

  Future<bool> validateAdminSession(AppUser profile) {
    return _firebase.validateAdminSession(profile.id);
  }

  Stream<AppUser?> watchCurrentUserProfile() {
    return _firebase.watchCurrentUserProfile();
  }

  Future<bool> updateProfile({
    required String name,
    required String department,
    required String phone,
    required String room,
    String homeAddress = '',
    String emergencyContact = '',
    String? photoUrl,
  }) async {
    final current = user;
    if (current == null) {
      error = 'No signed-in profile is available to update.';
      notifyListeners();
      return false;
    }
    return _guard(() async {
      final next = current.copyWith(
        name: name.trim(),
        department: department.trim(),
        phone: phone.trim(),
        room: room.trim(),
        homeAddress: homeAddress.trim(),
        emergencyContact: emergencyContact.trim(),
        photoUrl: photoUrl,
      );
      if (current.isAdmin) {
        await _firebase.updateUserProfile(next);
        user = next;
      } else {
        await _firebase.requestProfileUpdate(current: current, requested: next);
      }
    });
  }

  Future<bool> sendPasswordReset() async {
    final email = passwordResetEmail;
    if (email == null || email.trim().isEmpty) {
      error = 'No account email is available for password reset.';
      notifyListeners();
      return false;
    }
    return _guard(() => _firebase.sendPasswordResetEmail(email));
  }

  Future<bool> updateAdminPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    return _guard(
      () => _firebase.updateCurrentAccountPassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      ),
    );
  }

  Future<bool> completeTemporaryPasswordChange({
    required String currentPassword,
    required String newPassword,
  }) async {
    return _guard(() async {
      await _firebase.completeTemporaryPasswordChange(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      final current = user;
      if (current != null) {
        user = current.copyWith(requiresPasswordChange: false);
      }
    });
  }

  Future<bool> updateAdminEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    adminEmailUpdatePendingVerification = false;
    return _guard(() async {
      final updatedImmediately = await _firebase.updateCurrentAccountEmail(
        currentPassword: currentPassword,
        newEmail: newEmail,
      );
      adminEmailUpdatePendingVerification = !updatedImmediately;
      final current = user;
      if (current != null && updatedImmediately) {
        user = current.copyWith(email: newEmail.trim());
      }
    });
  }

  Future<bool> _guard(Future<void> Function() action) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await action();
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

  bool _sameProfile(AppUser? left, AppUser? right) {
    if (left == null || right == null) return left == right;
    return left.id == right.id &&
        left.name == right.name &&
        left.email == right.email &&
        left.department == right.department &&
        left.phone == right.phone &&
        left.room == right.room &&
        _sameStringList(left.rooms, right.rooms) &&
        left.role == right.role &&
        left.identityNumber == right.identityNumber &&
        left.course == right.course &&
        left.faculty == right.faculty &&
        left.currentSemester == right.currentSemester &&
        left.accessLevel == right.accessLevel &&
        left.status == right.status &&
        left.position == right.position &&
        left.homeAddress == right.homeAddress &&
        left.emergencyContact == right.emergencyContact &&
        left.hasFace == right.hasFace &&
        left.photoUrl == right.photoUrl &&
        left.pendingPhotoUrl == right.pendingPhotoUrl &&
        left.photoChangeRequestedAt == right.photoChangeRequestedAt &&
        left.photoUpdatedAt == right.photoUpdatedAt &&
        left.requiresPasswordChange == right.requiresPasswordChange &&
        left.temporaryPasswordIssuedAt == right.temporaryPasswordIssuedAt &&
        left.temporaryPasswordExpiresAt == right.temporaryPasswordExpiresAt;
  }

  bool _sameStringList(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    super.dispose();
  }
}
