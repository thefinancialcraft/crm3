class CallLogModel {
  final String id;
  final String number;
  final String? name;
  final String callType;
  final int duration;
  final DateTime timestamp;
  final String deviceId;

  CallLogModel({
    required this.id,
    required this.number,
    this.name,
    required this.callType,
    required this.duration,
    required this.timestamp,
    required this.deviceId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'name': name,
        'call_type': callType,
        'duration': duration,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'device_id': deviceId,
      };

  static CallLogModel fromMap(Map m) => CallLogModel(
        id: m['id'],
        number: m['number'],
        name: m['name'],
        callType: m['call_type'],
        duration: m['duration'],
        timestamp: DateTime.parse(m['timestamp']).toUtc(),
        deviceId: m['device_id'],
      );
}


