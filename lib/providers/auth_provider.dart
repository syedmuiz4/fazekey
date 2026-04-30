import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/firebase_service.dart';
import '../services/local_database_service.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._firebase, this._localDb);

  final FirebaseService _firebase;
  final LocalDatabaseService _localDb;
  AppUser? user;
  bool loading = true;
  bool darkMode = true;
  String? error;

  bool get isAuthenticated => user != null;

  Future<void> bootstrap() async {
    _firebase.authStateChanges().listen((firebaseUser) async {
      user = firebaseUser == null ? null : await _firebase.getUser(firebaseUser.uid);
      loading = false;
      notifyListeners();
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
  }) async {
    return _guard(() async {
      user = await _firebase.register(
        name: name,
        email: email,
        password: password,
        department: department,
        phone: phone,
        room: room,
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
}
