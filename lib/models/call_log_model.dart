class CallLogModel {
  final String id;
  final String number;
  final String? name;
  final String callType;
  final int duration;
  final DateTime timestamp;
  final String deviceId;
  final String? employeeId;
  final String? userName;
  final String? organizationId;
  final bool? isPersonal;
  final String? idx; // Composite key: number_timestamp_duration

  CallLogModel({
    required this.id,
    required this.number,
    this.name,
    required this.callType,
    required this.duration,
    required this.timestamp,
    required this.deviceId,
    this.employeeId,
    this.userName,
    this.organizationId,
    this.isPersonal,
    this.idx,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'name': name,
    'call_type': callType,
    'duration': duration,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'device_id': deviceId,
    'employee_id': employeeId,
    'user_name': userName,
    'organization_id': organizationId,
    'is_personal': isPersonal,
    'idx': idx,
  };

  static CallLogModel fromMap(Map m) => CallLogModel(
    id: m['id'],
    number: m['number'],
    name: m['name'],
    callType: m['call_type'],
    duration: m['duration'],
    timestamp: DateTime.parse(m['timestamp']).toUtc(),
    deviceId: m['device_id'],
    employeeId: m['employee_id'],
    userName: m['user_name'],
    organizationId: m['organization_id'],
    isPersonal: m['is_personal'],
    idx: m['idx'],
  );
}
