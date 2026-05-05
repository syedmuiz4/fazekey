class SecurityAlert {
  const SecurityAlert({
    required this.id,
    required this.title,
    required this.body,
    required this.severity,
    required this.timestamp,
    required this.read,
  });

  final String id;
  final String title;
  final String body;
  final String severity;
  final DateTime timestamp;
  final bool read;

  SecurityAlert copyWith({bool? read}) => SecurityAlert(
    id: id,
    title: title,
    body: body,
    severity: severity,
    timestamp: timestamp,
    read: read ?? this.read,
  );
}
