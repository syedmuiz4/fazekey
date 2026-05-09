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
  bool darkMode = true;
  String? error;

  bool get isAuthenticated => user != null;

  bool get isAdmin => user?.isAdmin == true;

  bool get isUser => isAuthenticated && !isAdmin;

  bool get hasSignedInAccount => _firebase.currentUserId != null;

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
      _profileSub = _firebase.watchUser(firebaseUser.uid).listen(
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
    });
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
    required String department,
    required String phone,
    required String room,
    String identityNumber = '',
  }) async {
    return _guard(() async {
      user = await _firebase.register(
        name: name,
        email: email,
        password: password,
        department: department,
        phone: phone,
        room: room,
        identityNumber: identityNumber,
      );
    });
  }

  Future<bool> logout() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
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
    final activeUser = user;
    if (activeUser != null) return _firebase.watchUser(activeUser.id);
    if (hasSignedInAccount) return _firebase.watchCurrentUserProfile();
    return Stream<AppUser?>.value(null);
  }

  Stream<AppUser?> watchCurrentUserProfile() {
    return _firebase.watchCurrentUserProfile();
  }

  Future<bool> updateProfile({
    required String name,
    required String department,
    required String phone,
    required String room,
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
      );
      await _firebase.updateUserProfile(next);
      user = next;
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
        left.role == right.role &&
        left.identityNumber == right.identityNumber &&
        left.course == right.course &&
        left.faculty == right.faculty &&
        left.currentSemester == right.currentSemester &&
        left.accessLevel == right.accessLevel &&
        left.hasFace == right.hasFace &&
        left.photoUrl == right.photoUrl;
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    super.dispose();
  }
}
