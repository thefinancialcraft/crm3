import 'package:hive_flutter/hive_flutter.dart';

class StorageService {
  static const callBucketBox = 'callBucket';
  static const syncedBucketBox = 'syncedBucket';
  static const metaBox = 'metaBox';
  static const appLogsBox = 'appLogs';

  static Future<void> init() async {
    await Hive.openBox(callBucketBox);
    await Hive.openBox(syncedBucketBox);
    await Hive.openBox(metaBox);
    await Hive.openBox(appLogsBox);
    // Migrate any legacy callBucket entries (stored as CallLogModel.toJson)
    // into the new wrapper shape:
    // { 'model': {...}, 'status': 'pending', 'attempts': 0, 'lastError': null }
    try {
      final box = Hive.box(callBucketBox);
      final keys = box.keys.toList();
      for (final k in keys) {
        try {
          final v = box.get(k);
          if (v is Map && v.containsKey('id') && v.containsKey('number')) {
            // legacy model map - wrap it
            final wrapped = {
              'model': Map<String, dynamic>.from(v),
              'status': 'pending',
              'attempts': 0,
              'lastError': null,
            };
            box.put(k, wrapped);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  static Box get callBucket => Hive.box(callBucketBox);
  static Box get syncedBucket => Hive.box(syncedBucketBox);
  static Box get appLogs => Hive.box(appLogsBox);
  static Box get meta => Hive.box(metaBox);

  // Convenience helpers
  static int getCallBucketCount() => callBucket.length;

  static Future<void> clearCallBucket() async {
    try {
      callBucket.clear();
      // keep syncedBucket intact
    } catch (_) {}
  }

  // Add missing methods
  static DateTime? getLastSync() {
    try {
      final v = meta.get('lastSync');
      if (v is String) return DateTime.parse(v);
    } catch (_) {}
    return null;
  }

  static void setLastSync(DateTime t) {
    try {
      meta.put('lastSync', t.toIso8601String());
    } catch (_) {}
  }

  static String getSyncStatus() {
    try {
      return meta.get('syncStatus')?.toString() ?? 'paused';
    } catch (_) {}
    return 'paused';
  }

  static void setSyncStatus(String s) {
    try {
      meta.put('syncStatus', s);
    } catch (_) {}
  }
}