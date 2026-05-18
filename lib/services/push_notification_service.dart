import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/security_alert.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class PushNotificationService {
  PushNotificationService({FirebaseMessaging? messaging})
    : _messaging = messaging ?? FirebaseMessaging.instance;

  static const AndroidNotificationChannel _intrusionChannel =
      AndroidNotificationChannel(
        'intrusion_alerts',
        'Security Notifications',
        description: 'High-priority intrusion and lockdown alerts.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final StreamController<SecurityAlert> _alertController =
      StreamController<SecurityAlert>.broadcast();

  static bool _localReady = false;

  static Stream<SecurityAlert> get alerts => _alertController.stream;

  final FirebaseMessaging _messaging;

  Future<void> initialize() async {
    await _initializeLocalNotifications();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    await _messaging.getToken();
    FirebaseMessaging.onMessage.listen(_showForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_publishOpenedMessage);
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _publishOpenedMessage(initialMessage);
    }
  }

  Future<void> showIntrusionAlert({
    required String title,
    required String body,
    int? badgeNumber,
  }) async {
    await _initializeLocalNotifications();
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'intrusion_alerts',
          'Security Notifications',
          channelDescription: 'High-priority intrusion and lockdown alerts.',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          number: badgeNumber,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          badgeNumber: badgeNumber,
        ),
      ),
    );
  }

  Future<void> clearDisplayedAlerts() async {
    await _initializeLocalNotifications();
    await _localNotifications.cancelAll();
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localReady) return;
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notification'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(initializationSettings);
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_intrusionChannel);
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _localReady = true;
  }

  Future<void> _showForegroundMessage(RemoteMessage message) async {
    final alert = _alertFromMessage(message);
    _alertController.add(alert);
    await showIntrusionAlert(title: alert.title, body: alert.body);
  }

  void _publishOpenedMessage(RemoteMessage message) {
    _alertController.add(_alertFromMessage(message));
  }

  SecurityAlert _alertFromMessage(RemoteMessage message) {
    final notification = message.notification;
    final title =
        notification?.title ??
        message.data['title']?.toString() ??
        'Security Alert';
    final body =
        notification?.body ??
        message.data['body']?.toString() ??
        'A security event requires attention.';
    return SecurityAlert(
      id: message.messageId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      body: body,
      severity: message.data['severity']?.toString() ?? 'High',
      timestamp: DateTime.now(),
      read: false,
    );
  }
}
