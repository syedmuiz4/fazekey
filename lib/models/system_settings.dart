import 'package:cloud_firestore/cloud_firestore.dart';

class SystemSettings {
  const SystemSettings({
    required this.globalLockdown,
    required this.afterHoursAlerts,
    required this.intrusionAlerts,
    required this.monitoringWindowLogging,
    required this.maintenanceMode,
    required this.lowLightEnhancement,
    required this.hardwarePowerSaveMode,
    required this.afterHoursStart,
    required this.afterHoursEnd,
    required this.semesterStart,
    required this.semesterEnd,
    required this.updatedAt,
    required this.administratorEmail,
  });

  final bool globalLockdown;
  final bool afterHoursAlerts;
  final bool intrusionAlerts;
  final bool monitoringWindowLogging;
  final bool maintenanceMode;
  final bool lowLightEnhancement;
  final bool hardwarePowerSaveMode;
  final int afterHoursStart;
  final int afterHoursEnd;
  final DateTime semesterStart;
  final DateTime semesterEnd;
  final DateTime updatedAt;
  final String administratorEmail;

  factory SystemSettings.defaults() => SystemSettings(
    globalLockdown: false,
    afterHoursAlerts: false,
    intrusionAlerts: true,
    monitoringWindowLogging: true,
    maintenanceMode: false,
    lowLightEnhancement: true,
    hardwarePowerSaveMode: false,
    afterHoursStart: 8,
    afterHoursEnd: 10,
    semesterStart: DateTime(2026, 3, 1),
    semesterEnd: DateTime(2026, 7, 31),
    updatedAt: DateTime.now(),
    administratorEmail: 'administrator@campus-access.local',
  );

  factory SystemSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return SystemSettings.defaults();
    return SystemSettings(
      globalLockdown: map['globalLockdown'] ?? false,
      afterHoursAlerts:
          map['afterHoursEnabled'] ?? map['afterHoursAlerts'] ?? false,
      intrusionAlerts: map['intrusionAlerts'] ?? true,
      monitoringWindowLogging: map['monitoringWindowLogging'] ?? true,
      maintenanceMode: map['maintenanceMode'] ?? false,
      lowLightEnhancement: map['lowLightEnhancement'] ?? true,
      hardwarePowerSaveMode: map['hardwarePowerSaveMode'] ?? false,
      afterHoursStart: map['accessWindowStart'] ?? map['afterHoursStart'] ?? 8,
      afterHoursEnd: map['accessWindowEnd'] ?? map['afterHoursEnd'] ?? 10,
      semesterStart:
          (map['semesterStart'] as Timestamp?)?.toDate() ??
          SystemSettings.defaults().semesterStart,
      semesterEnd:
          (map['semesterEnd'] as Timestamp?)?.toDate() ??
          SystemSettings.defaults().semesterEnd,
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      administratorEmail:
          map['administratorEmail'] ??
          map['adminEmail'] ??
          map['supportEmail'] ??
          'administrator@campus-access.local',
    );
  }

  Map<String, dynamic> toMap() => {
    'globalLockdown': globalLockdown,
    'system_status': globalLockdown ? 'lockdown' : 'normal',
    'afterHoursEnabled': afterHoursAlerts,
    'afterHoursAlerts': afterHoursAlerts,
    'intrusionAlerts': intrusionAlerts,
    'monitoringWindowLogging': monitoringWindowLogging,
    'maintenanceMode': maintenanceMode,
    'lowLightEnhancement': lowLightEnhancement,
    'hardwarePowerSaveMode': hardwarePowerSaveMode,
    'accessWindowStart': afterHoursStart,
    'accessWindowEnd': afterHoursEnd,
    'semesterStart': Timestamp.fromDate(semesterStart),
    'semesterEnd': Timestamp.fromDate(semesterEnd),
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

  bool shouldDenyScanForRole(String? role, DateTime now) {
    return shouldDenyScanAt(now);
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
    bool? maintenanceMode,
    bool? lowLightEnhancement,
    bool? hardwarePowerSaveMode,
    int? afterHoursStart,
    int? afterHoursEnd,
    DateTime? semesterStart,
    DateTime? semesterEnd,
    String? administratorEmail,
  }) => SystemSettings(
    globalLockdown: globalLockdown ?? this.globalLockdown,
    afterHoursAlerts: afterHoursAlerts ?? this.afterHoursAlerts,
    intrusionAlerts: intrusionAlerts ?? this.intrusionAlerts,
    monitoringWindowLogging:
        monitoringWindowLogging ?? this.monitoringWindowLogging,
    maintenanceMode: maintenanceMode ?? this.maintenanceMode,
    lowLightEnhancement: lowLightEnhancement ?? this.lowLightEnhancement,
    hardwarePowerSaveMode: hardwarePowerSaveMode ?? this.hardwarePowerSaveMode,
    afterHoursStart: afterHoursStart ?? this.afterHoursStart,
    afterHoursEnd: afterHoursEnd ?? this.afterHoursEnd,
    semesterStart: semesterStart ?? this.semesterStart,
    semesterEnd: semesterEnd ?? this.semesterEnd,
    updatedAt: DateTime.now(),
    administratorEmail: administratorEmail ?? this.administratorEmail,
  );
}
