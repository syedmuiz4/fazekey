import 'package:cloud_firestore/cloud_firestore.dart';

class IncidentReport {
  const IncidentReport({
    required this.id,
    required this.reporterId,
    required this.reporterName,
    required this.title,
    required this.severity,
    required this.areaName,
    required this.details,
    required this.status,
    required this.createdAt,
    this.reporterIdentityNumber = '',
    this.lastScannedLocation = '',
  });

  final String id;
  final String reporterId;
  final String reporterName;
  final String reporterIdentityNumber;
  final String title;
  final String severity;
  final String areaName;
  final String lastScannedLocation;
  final String details;
  final String status;
  final DateTime createdAt;

  factory IncidentReport.fromMap(String id, Map<String, dynamic> map) {
    return IncidentReport(
      id: id,
      reporterId: map['reporterId'] ?? '',
      reporterName: map['reporterName'] ?? '',
      reporterIdentityNumber: map['reporterIdentityNumber'] ?? '',
      title: map['title'] ?? '',
      severity: map['severity'] ?? 'High',
      areaName: map['areaName'] ?? '',
      lastScannedLocation: map['lastScannedLocation'] ?? map['areaName'] ?? '',
      details: map['details'] ?? '',
      status: map['status'] ?? 'open',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
