import 'package:cloud_firestore/cloud_firestore.dart';

class SystemSettings {
  const SystemSettings({
    required this.globalLockdown,
    required this.afterHoursAlerts,
    required this.intrusionAlerts,
    required this.monitoringWindowLogging,
    required this.afterHoursStart,
    required this.afterHoursEnd,
    required this.updatedAt,
    required this.administratorEmail,
  });

  final bool globalLockdown;
  final bool afterHoursAlerts;
  final bool intrusionAlerts;
  final bool monitoringWindowLogging;
  final int afterHoursStart;
  final int afterHoursEnd;
  final DateTime updatedAt;
  final String administratorEmail;

  factory SystemSettings.defaults() => SystemSettings(
    globalLockdown: false,
    afterHoursAlerts: false,
    intrusionAlerts: true,
    monitoringWindowLogging: true,
    afterHoursStart: 8,
    afterHoursEnd: 10,
    updatedAt: DateTime.now(),
    administratorEmail: 'administrator@fazekey.app',
  );

  factory SystemSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return SystemSettings.defaults();
    return SystemSettings(
      globalLockdown: map['globalLockdown'] ?? false,
      afterHoursAlerts:
          map['afterHoursEnabled'] ?? map['afterHoursAlerts'] ?? false,
      intrusionAlerts: map['intrusionAlerts'] ?? true,
      monitoringWindowLogging: map['monitoringWindowLogging'] ?? true,
      afterHoursStart: map['accessWindowStart'] ?? map['afterHoursStart'] ?? 8,
      afterHoursEnd: map['accessWindowEnd'] ?? map['afterHoursEnd'] ?? 10,
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      administratorEmail:
          map['administratorEmail'] ??
          map['adminEmail'] ??
          map['supportEmail'] ??
          'administrator@fazekey.app',
    );
  }

  Map<String, dynamic> toMap() => {
    'globalLockdown': globalLockdown,
    'system_status': globalLockdown ? 'lockdown' : 'normal',
    'afterHoursEnabled': afterHoursAlerts,
    'afterHoursAlerts': afterHoursAlerts,
    'intrusionAlerts': intrusionAlerts,
    'monitoringWindowLogging': monitoringWindowLogging,
    'accessWindowStart': afterHoursStart,
    'accessWindowEnd': afterHoursEnd,
    'administratorEmail': administratorEmail,
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  bool get isAfterHoursActive => shouldDenyScanAt(DateTime.now());

  bool get isWithinAfterHoursWindow => !isWithinAccessWindow;

  bool get isWithinAccessWindow => isAccessAllowedAt(
    DateTime.now(),
    startHour: afterHoursStart,
    endHour: afterHoursEnd,
  );

  bool shouldDenyScanAt(DateTime now) {
    if (!afterHoursAlerts) return false;
    return !isAccessAllowedAt(
      now,
      startHour: afterHoursStart,
      endHour: afterHoursEnd,
    );
  }

  static bool isAccessAllowedAt(
    DateTime now, {
    int startHour = 8,
    int endHour = 10,
  }) {
    final isWeekday =
        now.weekday >= DateTime.monday && now.weekday <= DateTime.friday;
    if (!isWeekday) return false;
    if (startHour == endHour) return true;
    if (startHour < endHour) {
      return now.hour >= startHour && now.hour < endHour;
    }
    return now.hour >= startHour || now.hour < endHour;
  }

  SystemSettings copyWith({
    bool? globalLockdown,
    bool? afterHoursAlerts,
    bool? intrusionAlerts,
    bool? monitoringWindowLogging,
    int? afterHoursStart,
    int? afterHoursEnd,
    String? administratorEmail,
  }) => SystemSettings(
    globalLockdown: globalLockdown ?? this.globalLockdown,
    afterHoursAlerts: afterHoursAlerts ?? this.afterHoursAlerts,
    intrusionAlerts: intrusionAlerts ?? this.intrusionAlerts,
    monitoringWindowLogging:
        monitoringWindowLogging ?? this.monitoringWindowLogging,
    afterHoursStart: afterHoursStart ?? this.afterHoursStart,
    afterHoursEnd: afterHoursEnd ?? this.afterHoursEnd,
    updatedAt: DateTime.now(),
    administratorEmail: administratorEmail ?? this.administratorEmail,
  );
}
