import 'dart:async';
import 'dart:ui';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter/material.dart';
import 'constants.dart';

class CallLogService {
  late SupabaseClient _supabase;
  Timer? _autoSyncTimer;
  // Timer? _callLogCheckTimer; // removed unused field
  final int _autoSyncIntervalSeconds = 60; // auto-sync every 60s (adjustable)
  final String _deviceId = 'device_1';
  final String _syncMetaTable = 'sync_meta';
  int? _lastKnownCallCount;

  DateTime? _lastSyncTime;
  int _lastSyncCount = 0;

  // Callback for sync updates
  Function? onSyncComplete;

  // Background service initialization
  static Future<void> initializeBackgroundService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: backgroundCallback,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'call_sync_service',
        initialNotificationTitle: 'Call Sync Service',
        initialNotificationContent: 'Running in background',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: backgroundCallback,
        onBackground: onIosBackground,
      ),
    );
  }

  // Background callback for Android and iOS foreground
  @pragma('vm:entry-point')
  static Future<void> backgroundCallback(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    // Create instance and initialize
    final callLogService = CallLogService();
    await Supabase.initialize(
      url: SupabaseConstants.supabaseUrl,
      anonKey: SupabaseConstants.supabaseAnonKey,
    );

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    // Start periodic check for new calls
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      await callLogService.checkAndSyncNewCalls();
    });
  }

  // iOS background handler
  @pragma('vm:entry-point')
  static bool onIosBackground(ServiceInstance service) {
    WidgetsFlutterBinding.ensureInitialized();
    return true;
  }

  // Check for new calls and sync if found
  Future<void> checkAndSyncNewCalls() async {
    try {
      final logs = await readCallLogs();
      if (logs == null) return;

      final currentCount = logs.length;

      // If this is first check, just store the count
      if (_lastKnownCallCount == null) {
        _lastKnownCallCount = currentCount;
        return;
      }

      // If we have new calls
      if (currentCount > _lastKnownCallCount!) {
        debugPrint('New calls detected! Syncing...');
        await uploadNewCallLogs();
        _lastKnownCallCount = currentCount;
      }
    } catch (e) {
      debugPrint('Error checking for new calls: $e');
    }
  }

  CallLogService() {
    _initSupabase();
  }

  void _initSupabase() {
    _supabase = Supabase.instance.client;
  }

  Future<bool> requestPermission() async {
    // For Android, we need READ_CALL_LOG permission
    // The permission_handler package uses Permission.phone for call log permissions
    final status = await Permission.phone.request();
    return status == PermissionStatus.granted;
  }

  Future<List<CallLogEntry>?> readCallLogs() async {
    try {
      debugPrint('Reading call logs from device...');
      final Iterable<CallLogEntry> callLogs = await CallLog.get();
      debugPrint('Successfully read ${callLogs.length} call logs');
      return callLogs.toList();
    } catch (e) {
      // Using debugPrint instead of print for development only
      debugPrint('Error reading call logs: $e');
      return null;
    }
  }

  /// Uploads only call logs that are newer than the last synced timestamp.
  /// Uses a small `sync_meta` table to store the last synced timestamp per device.
  /// Returns number of records uploaded, or -1 on error
  Future<int> uploadNewCallLogs() async {
    try {
      final lastSyncedMs = await _getLastSyncedTimestampMs();
      debugPrint('Last synced timestamp (ms): $lastSyncedMs');

      final callLogs = await readCallLogs();
      if (callLogs == null || callLogs.isEmpty) {
        debugPrint('No call logs to upload');
        return 0;
      }

      // Get existing call logs from Supabase for this device
      final existingLogs = await _supabase
          .from('call_logs')
          .select('number, timestamp, duration, call_type')
          .eq('device_id', _deviceId);

      // Create a Set of unique call identifiers from existing logs
      final existingCallSet = Set<String>.from(
        existingLogs.map(
          (log) =>
              '${log['number']}_${log['timestamp']}_${log['duration']}_${log['call_type']}',
        ),
      );

      // Filter out duplicate calls
      final newLogs =
          callLogs.where((log) {
            // Create unique identifier for this call
            final callId =
                '${log.number}_${log.timestamp != null ? DateTime.fromMillisecondsSinceEpoch(log.timestamp!).toIso8601String() : ''}_${log.duration}_${_getCallTypeString(log.callType)}';

            // Only include if it's not already in Supabase
            return !existingCallSet.contains(callId);
          }).toList();

      if (newLogs.isEmpty) {
        debugPrint('No new unique call logs to upload.');
        return 0;
      }

      debugPrint(
        'Preparing to upload ${newLogs.length} new unique call logs to Supabase...',
      );

      final List<Map<String, dynamic>> logsData =
          newLogs.map((log) {
            return {
              'id': const Uuid().v4(),
              'number': log.number,
              'name': log.name,
              'call_type': _getCallTypeString(log.callType),
              'duration': log.duration,
              'timestamp':
                  log.timestamp != null
                      ? DateTime.fromMillisecondsSinceEpoch(
                        log.timestamp!,
                      ).toIso8601String()
                      : DateTime.now().toIso8601String(),
              'device_id': _deviceId,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            };
          }).toList();

      debugPrint('Uploading batch of ${logsData.length} records...');

      await _supabase.from('call_logs').insert(logsData).select();

      // Update last synced timestamp to the maximum timestamp we uploaded
      final maxTs = newLogs
          .map((e) => e.timestamp ?? 0)
          .reduce((a, b) => a > b ? a : b);
      await _updateLastSyncedTimestampMs(maxTs);

      // Update sync info
      _lastSyncTime = DateTime.now();
      _lastSyncCount = logsData.length;

      debugPrint('Upload successful and last synced updated to $maxTs');
      return logsData.length;
    } catch (e, stackTrace) {
      debugPrint('Error uploading call logs: $e');
      debugPrint('Stack trace: $stackTrace');
      return -1;
    }
  }

  Future<int> _getLastSyncedTimestampMs() async {
    try {
      final resp =
          await _supabase
              .from(_syncMetaTable)
              .select('last_synced_at')
              .eq('device_id', _deviceId)
              .maybeSingle();

      if (resp == null) return 0;

      final lastSyncedStr = resp['last_synced_at'] as String?;
      if (lastSyncedStr == null) return 0;
      final dt = DateTime.tryParse(lastSyncedStr);
      return dt != null ? dt.millisecondsSinceEpoch : 0;
    } catch (e) {
      debugPrint('Error fetching last synced timestamp: $e');
      return 0;
    }
  }

  Future<void> _updateLastSyncedTimestampMs(int tsMs) async {
    try {
      final dtIso =
          DateTime.fromMillisecondsSinceEpoch(tsMs).toUtc().toIso8601String();

      // Upsert into sync_meta table for this device
      await _supabase.from(_syncMetaTable).upsert({
        'device_id': _deviceId,
        'last_synced_at': dtIso,
      });
    } catch (e) {
      debugPrint('Error updating last synced timestamp: $e');
    }
  }

  /// Start automatic periodic syncing while the app is active.
  void startAutoSync(Function? onSync) {
    onSyncComplete = onSync;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(
      Duration(seconds: _autoSyncIntervalSeconds),
      (timer) async {
        debugPrint('[AutoSync] Triggering automatic sync...');
        final syncedCount = await uploadNewCallLogs();
        if (syncedCount > 0 && onSyncComplete != null) {
          onSyncComplete!();
        }
      },
    );
  }

  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  Future<bool> uploadCallLogs(List<CallLogEntry> callLogs) async {
    try {
      debugPrint(
        'Preparing to upload ${callLogs.length} call logs to Supabase...',
      );

      final List<Map<String, dynamic>> logsData =
          callLogs.map((log) {
            return {
              'id': const Uuid().v4(),
              'number': log.number,
              'name': log.name,
              'call_type': _getCallTypeString(log.callType),
              'duration': log.duration,
              'timestamp':
                  log.timestamp != null
                      ? DateTime.fromMillisecondsSinceEpoch(
                        log.timestamp!,
                      ).toIso8601String()
                      : DateTime.now().toIso8601String(),
              'device_id': 'device_1', 
              'created_at': DateTime.now().toUtc().toIso8601String(),
            };
          }).toList();

      debugPrint('Uploading batch of ${logsData.length} records...');

      // Batch insert all call logs
      final response =
          await _supabase.from('call_logs').insert(logsData).select();

      debugPrint('Upload response: $response');

      // For Supabase, a successful insert typically returns a list of inserted records
      // If we get here without exception, the insert was successful
      debugPrint('Upload successful');
      return true;
    } catch (e, stackTrace) {
      // Using debugPrint instead of print for development only
      debugPrint('Error uploading call logs: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  Future<bool> sendFakeData() async {
    try {
      debugPrint('Sending fake test data to Supabase...');

      // Generate fake call log data
      final fakeData = [
        {
          'id': const Uuid().v4(),
          'number': '+1234567890',
          'name': 'John Doe',
          'call_type': 'incoming',
          'duration': 120,
          'timestamp':
              DateTime.now()
                  .subtract(const Duration(hours: 1))
                  .toUtc()
                  .toIso8601String(),
          'device_id': 'test_device_1',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
        {
          'id': const Uuid().v4(),
          'number': '+1987654321',
          'name': 'Jane Smith',
          'call_type': 'outgoing',
          'duration': 45,
          'timestamp':
              DateTime.now()
                  .subtract(const Duration(hours: 2))
                  .toUtc()
                  .toIso8601String(),
          'device_id': 'test_device_1',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
        {
          'id': const Uuid().v4(),
          'number': '+1555123456',
          'name': null,
          'call_type': 'missed',
          'duration': 0,
          'timestamp':
              DateTime.now()
                  .subtract(const Duration(days: 1))
                  .toUtc()
                  .toIso8601String(),
          'device_id': 'test_device_1',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
      ];

      debugPrint('Inserting ${fakeData.length} fake records...');

      // Insert fake data with error handling
      try {
        final response =
            await _supabase.from('call_logs').insert(fakeData).select();

        debugPrint('Fake data upload response: $response');

        // For Supabase, a successful insert typically returns a list of inserted records
        // If we get here without exception, the insert was successful
        debugPrint('Successfully sent fake test data to Supabase');
        return true;
      } catch (supabaseError, supabaseStackTrace) {
        debugPrint('Supabase specific error: $supabaseError');
        debugPrint('Supabase stack trace: $supabaseStackTrace');
        return false;
      }
    } catch (e, stackTrace) {
      // Using debugPrint instead of print for development only
      debugPrint('Error sending fake data: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  String _getCallTypeString(CallType? callType) {
    switch (callType) {
      case CallType.incoming:
        return 'incoming';
      case CallType.outgoing:
        return 'outgoing';
      case CallType.missed:
        return 'missed';
      case CallType.blocked:
        return 'blocked';
      case CallType.rejected:
        return 'rejected';
      case CallType.answeredExternally:
        return 'answered_externally';
      default:
        return 'unknown';
    }
  }

  // Get last sync info
  DateTime? getLastSyncTime() => _lastSyncTime;
  int getLastSyncCount() => _lastSyncCount;

  // Get latest call log stats
  Future<Map<String, dynamic>> getCallLogStats() async {
    try {
      final logs = await readCallLogs();
      if (logs == null || logs.isEmpty) {
        return {'total': 0, 'latest': null, 'missed': 0};
      }

      // Sort by timestamp descending
      logs.sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));

      return {
        'total': logs.length,
        'latest':
            logs.first.timestamp != null
                ? DateTime.fromMillisecondsSinceEpoch(logs.first.timestamp!)
                : null,
        'missed': logs.where((log) => log.callType == CallType.missed).length,
      };
    } catch (e) {
      debugPrint('Error getting call log stats: $e');
      return {'total': 0, 'latest': null, 'missed': 0};
    }
  }
}
