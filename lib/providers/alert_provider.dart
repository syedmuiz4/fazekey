import 'dart:async';

import 'package:flutter/material.dart';

import '../models/security_alert.dart';
import '../services/push_notification_service.dart';

class AlertProvider extends ChangeNotifier {
  AlertProvider(this._push);

  final PushNotificationService _push;
  final List<SecurityAlert> _alerts = [];
  StreamSubscription<SecurityAlert>? _sub;

  List<SecurityAlert> get alerts => List.unmodifiable(_alerts);

  int get unreadCount => _alerts.where((alert) => !alert.read).length;

  void listen() {
    _sub ??= PushNotificationService.alerts.listen(addAlert);
  }

  Future<void> raiseIntrusionAlert({
    required String title,
    required String body,
    String severity = 'High',
  }) async {
    final alert = SecurityAlert(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      body: body,
      severity: severity,
      timestamp: DateTime.now(),
      read: false,
    );
    addAlert(alert);
    await _push.showIntrusionAlert(
      title: title,
      body: body,
      badgeNumber: unreadCount,
    );
  }

  void addAlert(SecurityAlert alert) {
    _alerts.removeWhere((item) => item.id == alert.id);
    _alerts.insert(0, alert);
    if (_alerts.length > 80) {
      _alerts.removeRange(80, _alerts.length);
    }
    notifyListeners();
  }

  Future<void> markAllRead() async {
    if (unreadCount > 0) {
      for (var i = 0; i < _alerts.length; i++) {
        _alerts[i] = _alerts[i].copyWith(read: true);
      }
    }
    await _push.clearDisplayedAlerts();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
