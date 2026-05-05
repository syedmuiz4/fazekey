import 'dart:async';

import 'package:flutter/material.dart';

import '../models/system_settings.dart';
import '../services/firebase_service.dart';

class SystemProvider extends ChangeNotifier {
  SystemProvider(this._firebase);

  final FirebaseService _firebase;
  StreamSubscription<SystemSettings>? _sub;
  SystemSettings settings = SystemSettings.defaults();
  bool loading = false;
  String? error;

  void listen() {
    _sub ??= _firebase.watchSystemSettings().listen(
      (value) {
        settings = value;
        notifyListeners();
      },
      onError: (e) {
        error = e.toString();
        notifyListeners();
      },
    );
  }

  Future<void> save(SystemSettings next) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _firebase.saveSystemSettings(next);
      settings = next;
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> toggleLockdown(bool value) =>
      save(settings.copyWith(globalLockdown: value));

  Future<void> activateEmergencyLockdown() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _firebase.activateEmergencyLockdown();
      settings = settings.copyWith(globalLockdown: true);
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> toggleAfterHoursAlerts(bool value) =>
      save(settings.copyWith(afterHoursAlerts: value));

  Future<void> toggleIntrusionAlerts(bool value) =>
      save(settings.copyWith(intrusionAlerts: value));

  Future<void> toggleMonitoringWindowLogging(bool value) =>
      save(settings.copyWith(monitoringWindowLogging: value));

  Future<void> updateAfterHours({required int start, required int end}) {
    return save(settings.copyWith(afterHoursStart: start, afterHoursEnd: end));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
