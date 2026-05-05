import 'package:hive_flutter/hive_flutter.dart';

class StorageService {
  static const callBucketBox = 'callBucket';
  static const syncedBucketBox = 'syncedBucket';
  static const failedBucketBox = 'failedBucket'; // ❌ NEW: For problematic leads
  static const metaBox = 'metaBox';
  static const appLogsBox = 'appLogs';

  static Future<void> init() async {
    // isBoxOpen check — double init crash prevent karta hai
    if (!Hive.isBoxOpen(callBucketBox)) {
      await Hive.openBox(callBucketBox);
    }
    if (!Hive.isBoxOpen(syncedBucketBox)) {
      await Hive.openBox(syncedBucketBox);
    }
    if (!Hive.isBoxOpen(failedBucketBox)) {
      await Hive.openBox(failedBucketBox);
    }
    if (!Hive.isBoxOpen(metaBox)) {
      await Hive.openBox(metaBox);
    }
    if (!Hive.isBoxOpen(appLogsBox)) {
      await Hive.openBox(appLogsBox);
    }

    // Migration logic same rahega...
    try {
      final box = Hive.box(callBucketBox);
      for (final k in box.keys.toList()) {
        try {
          final v = box.get(k);
          if (v is Map && v.containsKey('id') && v.containsKey('number')) {
            box.put(k, {
              'model': Map<String, dynamic>.from(v),
              'status': 'pending',
              'attempts': 0,
              'lastError': null,
            });
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  static Box get callBucket => Hive.box(callBucketBox);
  static Box get syncedBucket => Hive.box(syncedBucketBox);
  static Box get failedBucket => Hive.box(failedBucketBox); // ❌ Getter
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

  // --- CENTRAL USER STORAGE (Single Source of Truth) ---
  
  static Map<String, dynamic>? getUser() {
    try {
      final v = meta.get('userInfo');
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
  }

  /// 🔐 Sets the entire login payload provided by the Web/Flutter Bridge
  static Future<void> setUserSession(Map<String, dynamic> payload) async {
    try {
      await meta.put('userInfo', payload);
      await meta.put('isLoggedIn', payload['login'] ?? true);
      // Automatically update organization context
      if (payload['organization_id'] != null) {
        await meta.put('lastOrgId', payload['organization_id']);
      }
    } catch (_) {}
  }

  /// 🛑 Clears everything on Logout
  static Future<void> clearUserSession() async {
    try {
      await meta.delete('userInfo');
      await meta.delete('isLoggedIn');
      await meta.delete('lastOrgId');
      // Optional: Clear temporary buckets if needed
      // await callBucket.clear(); 
    } catch (_) {}
  }

  // --- INDIVIDUAL GETTERS (For easy access across app) ---

  static String? getEmployeeId() => getUser()?['employee_id']?.toString();
  static String? getOrgId() => getUser()?['organization_id']?.toString();
  static String? getUserName() => getUser()?['user_name']?.toString();
  static String? getUserRole() => getUser()?['role']?.toString();
  static bool isLoggedIn() => meta.get('isLoggedIn') ?? (getUser() != null);

  static Map<String, dynamic> getDeviceContext() {
    return {
      'lastSync': getLastSync()?.toIso8601String(),
      'syncStatus': getSyncStatus(),
      'simId': getDefaultSim(),
      'slot': getDefaultSimSlot(),
    };
  }

  // User Sessions Persistence
  static List<Map<String, dynamic>> getUserSessions() {
    try {
      final v = meta.get('userSessions');
      if (v is List) {
        return List<Map<String, dynamic>>.from(
          v.map((e) => Map<String, dynamic>.from(e)),
        );
      }
    } catch (_) {}
    return [];
  }

  static Future<void> saveUserSessions(
    List<Map<String, dynamic>> sessions,
  ) async {
    try {
      await meta.put('userSessions', sessions);
    } catch (_) {}
  }

  // SIM Preference
  static String? getDefaultSim() {
    try {
      return meta.get('defaultSimId')?.toString();
    } catch (_) {}
    return null;
  }

  static int? getDefaultSimSlot() {
    try {
      final v = meta.get('defaultSimSlot');
      if (v is int) return v;
      if (v is String) return int.tryParse(v);
    } catch (_) {}
    return null;
  }

  static Future<void> setDefaultSim(String? simId, [int? slotIndex]) async {
    try {
      if (simId == null) {
        await meta.delete('defaultSimId');
        await meta.delete('defaultSimSlot');
      } else {
        await meta.put('defaultSimId', simId);
        if (slotIndex != null) {
          await meta.put('defaultSimSlot', slotIndex);
        }
      }
    } catch (_) {}
  }

  // Last Scanned Pointer
  static int? getLastScannedAt() {
    try {
      final v = meta.get('lastScannedAt');
      if (v is int) return v;
    } catch (_) {}
    return null;
  }

  static Future<void> setLastScannedAt(int timestamp) async {
    try {
      await meta.put('lastScannedAt', timestamp);
    } catch (_) {}
  }

  // Personal Numbers
  static List<String> getPersonalNumbers() {
    try {
      final v = meta.get('personalNumbers');
      if (v is List) return List<String>.from(v);
    } catch (_) {}
    return [];
  }

  static Future<void> setPersonalNumbers(List<String> numbers) async {
    try {
      await meta.put('personalNumbers', numbers);
    } catch (_) {}
  }

  // --- UPDATE DISMISSAL HELPERS ---
  static DateTime? getLastUpdateDismissed() {
    try {
      final v = meta.get('lastUpdateDismissed');
      if (v is String) return DateTime.parse(v);
    } catch (_) {}
    return null;
  }

  static Future<void> setUpdateDismissed() async {
    try {
      await meta.put('lastUpdateDismissed', DateTime.now().toIso8601String());
    } catch (_) {}
  }
}
