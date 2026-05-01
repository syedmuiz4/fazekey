import 'package:cloud_firestore/cloud_firestore.dart';

class SystemSettings {
  const SystemSettings({
    required this.globalLockdown,
    required this.afterHoursAlerts,
    required this.intrusionAlerts,
    required this.afterHoursStart,
    required this.afterHoursEnd,
    required this.updatedAt,
  });

  final bool globalLockdown;
  final bool afterHoursAlerts;
  final bool intrusionAlerts;
  final int afterHoursStart;
  final int afterHoursEnd;
  final DateTime updatedAt;

  factory SystemSettings.defaults() => SystemSettings(
        globalLockdown: false,
        afterHoursAlerts: true,
        intrusionAlerts: true,
        afterHoursStart: 18,
        afterHoursEnd: 7,
        updatedAt: DateTime.now(),
      );

  factory SystemSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return SystemSettings.defaults();
    return SystemSettings(
      globalLockdown: map['globalLockdown'] ?? false,
      afterHoursAlerts: map['afterHoursAlerts'] ?? true,
      intrusionAlerts: map['intrusionAlerts'] ?? true,
      afterHoursStart: map['afterHoursStart'] ?? 18,
      afterHoursEnd: map['afterHoursEnd'] ?? 7,
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'globalLockdown': globalLockdown,
        'afterHoursAlerts': afterHoursAlerts,
        'intrusionAlerts': intrusionAlerts,
        'afterHoursStart': afterHoursStart,
        'afterHoursEnd': afterHoursEnd,
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  bool get isAfterHours {
    final hour = DateTime.now().hour;
    if (afterHoursStart == afterHoursEnd) return true;
    if (afterHoursStart < afterHoursEnd) {
      return hour >= afterHoursStart && hour < afterHoursEnd;
    }
    return hour >= afterHoursStart || hour < afterHoursEnd;
  }

  SystemSettings copyWith({
    bool? globalLockdown,
    bool? afterHoursAlerts,
    bool? intrusionAlerts,
    int? afterHoursStart,
    int? afterHoursEnd,
  }) =>
      SystemSettings(
        globalLockdown: globalLockdown ?? this.globalLockdown,
        afterHoursAlerts: afterHoursAlerts ?? this.afterHoursAlerts,
        intrusionAlerts: intrusionAlerts ?? this.intrusionAlerts,
        afterHoursStart: afterHoursStart ?? this.afterHoursStart,
        afterHoursEnd: afterHoursEnd ?? this.afterHoursEnd,
        updatedAt: DateTime.now(),
      );
}
