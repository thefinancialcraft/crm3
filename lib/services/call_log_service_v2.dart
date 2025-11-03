import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:call_log/call_log.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:call_state_handler/call_state_handler.dart';
import 'package:call_state_handler/models/call_state.dart' as call_state_models;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/call_log_model.dart';
import 'storage_service.dart';
import '../utils/device_utils.dart';
import 'logger_service.dart';
import 'sync_service_v2.dart';
import 'notification_service.dart';

class CallLogService {
  static CallLogService? _instance;
  static final ValueNotifier<bool> callActiveNotifier = ValueNotifier<bool>(false);
  
  // Sync state flags and keys
  static const String _firstSyncKey = 'is_first_sync';
  static const String _lastSyncTimeKey = 'last_sync_time';
  static const String _lastSyncIdKey = 'last_sync_call_id';
  static const int _maxRetryAttempts = 3;
  
  // Instance variables for state
  bool _isOnCallRealTime = false;
  StreamSubscription? _callStateSubscription;
  Timer? _postCallSyncTimer;
  Timer? _nextSyncTimer;

  CallLogService() {
    _instance = this;
  }
  
  static Future<DateTime?> getLastSyncTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_lastSyncTimeKey);
      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    } catch (e) {
      LoggerService.warn('Failed to get last sync time: $e');
    }
    return null;
  }

  static Future<void> updateLastSync(String callId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastSyncTimeKey, DateTime.now().millisecondsSinceEpoch);
      await prefs.setString(_lastSyncIdKey, callId);
      LoggerService.info('Updated last sync info: $callId');
    } catch (e) {
      LoggerService.warn('Failed to update last sync info: $e');
    }
  }

  static bool get isOnCallRealTime => _instance?._isOnCallRealTime ?? false;

  static Future<bool> isFirstSyncCompleted() async {
    if (kIsWeb) return true;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_firstSyncKey) ?? false;
    } catch (e) {
      LoggerService.warn('Failed to check first sync status: $e');
      return false;
    }
  }

  static Future<void> markFirstSyncCompleted() async {
    if (kIsWeb) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_firstSyncKey, true);
      LoggerService.info('First sync marked as completed');
    } catch (e) {
      LoggerService.warn('Failed to mark first sync as completed: $e');
    }
  }

  void startAutoSync({
    Duration interval = const Duration(minutes: 1),
    Function(int pending, int synced)? onProgress,
  }) {
    LoggerService.info('Auto sync is disabled - use manual sync after call ends');
  }

  Future<bool> sendFakeData() async {
    try {
      final deviceId = await DeviceUtils.getDeviceId();
      final now = DateTime.now().toUtc();
      final examples = [
        {
          'number': '+10000000001',
          'name': 'Fake One',
          'call_type': 'incoming',
          'duration': 12,
          'timestamp': now.subtract(const Duration(minutes: 5)).toIso8601String(),
        },
        {
          'number': '+10000000002',
          'name': 'Fake Two',
          'call_type': 'outgoing',
          'duration': 34,
          'timestamp': now.subtract(const Duration(minutes: 10)).toIso8601String(),
        },
        {
          'number': '+10000000003',
          'name': null,
          'call_type': 'missed',
          'duration': 0,
          'timestamp': now.subtract(const Duration(hours: 1)).toIso8601String(),
        },
      ];

      for (final e in examples) {
        final timestamp = DateTime.parse(e['timestamp'] as String).toUtc();
        final id = _generateId(e['number'] as String, timestamp);
        final model = CallLogModel(
          id: id,
          number: e['number'] as String,
          name: e['name'] as String?,
          callType: e['call_type'] as String,
          duration: e['duration'] as int,
          timestamp: timestamp,
          deviceId: deviceId,
        );
        final wrapped = {
          'model': model.toJson(),
          'status': 'pending',
          'attempts': 0,
          'lastError': null,
        };
        StorageService.callBucket.put(id, wrapped);
        LoggerService.info('sendFakeData: enqueued $id');
      }
      return true;
    } catch (e, st) {
      LoggerService.error('sendFakeData failed', e, st);
      return false;
    }
  }

  Future<int> scanAndEnqueueNewCalls({DateTime? dateFrom}) async {
    if (kIsWeb) {
      LoggerService.info('CallLogService.scanAndEnqueueNewCalls skipped on Web');
      return 0;
    }

    LoggerService.info('CallLogService.scanAndEnqueueNewCalls started');
    try {
      final lastSync = dateFrom ?? await CallLogService.getLastSyncTime();
      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
      final cutoff = lastSync ?? threeDaysAgo;

      final currentDeviceId = await DeviceUtils.getDeviceId();
      final supabase = Supabase.instance.client;
      
      LoggerService.info('Fetching existing calls from Supabase since ${cutoff.toIso8601String()}');
      final existingCalls = await supabase
          .from('call_logs')
          .select('number,timestamp,duration,call_type')
          .eq('device_id', currentDeviceId)
          .gte('timestamp', cutoff.toIso8601String());
      
      final existingSet = <String>{};
      for (final call in existingCalls as List) {
        try {
          final number = call['number']?.toString() ?? '';
          final timestamp = call['timestamp']?.toString() ?? '';
          final duration = call['duration']?.toString() ?? '';
          final callType = call['call_type']?.toString() ?? '';
          final key = [number, timestamp, duration, callType].join('_');
          existingSet.add(key);
        } catch (e) {
          LoggerService.warn('Failed to process existing call: $e');
        }
      }
      LoggerService.info('Found ${existingSet.length} existing calls in Supabase');

      final Iterable<CallLogEntry> entries = await CallLog.get();
      
      final filteredEntries = entries.where((e) {
        final ts = DateTime.fromMillisecondsSinceEpoch(e.timestamp ?? 0);
        return ts.isAfter(cutoff);
      }).toList();
      LoggerService.info('Found ${filteredEntries.length} entries newer than ${cutoff.toUtc().toIso8601String()}');
      
      var added = 0;
      for (final e in filteredEntries) {
        final ts = DateTime.fromMillisecondsSinceEpoch(e.timestamp ?? 0);
        final id = _generateId(e.number ?? '', ts);
        
        final existingInSync = StorageService.syncedBucket.get(id);
        final existingInPending = StorageService.callBucket.get(id);
        final isLocalDuplicate = existingInSync != null || existingInPending != null;
        
        if (!isLocalDuplicate) {
          final number = e.number ?? '';
          final timestamp = ts.toUtc().toIso8601String();
          final duration = (e.duration ?? 0).toString();
          final callType = _mapType(e.callType);
          final key = [number, timestamp, duration, callType].join('_');
          
          if (!existingSet.contains(key)) {
            final model = CallLogModel(
              id: id,
              number: number,
              name: e.name,
              callType: callType,
              duration: e.duration ?? 0,
              timestamp: ts.toUtc(),
              deviceId: currentDeviceId,
            );
            final wrapped = {
              'model': model.toJson(),
              'status': 'pending',
              'attempts': 0,
              'lastError': null,
            };
            StorageService.callBucket.put(id, wrapped);
            added++;
            LoggerService.info('Enqueued new call: $id (${model.number})');
          } else {
            LoggerService.info('Skipping duplicate call in Supabase: $id ($number)');
          }
        } else {
          LoggerService.info('Skipping local duplicate call: $id');
        }
      }
      LoggerService.info('CallLogService.scanAndEnqueueNewCalls completed; added=$added');
      return added;
    } catch (e) {
      LoggerService.error('CallLogService.scanAndEnqueueNewCalls failed: $e');
      return 0;
    }
  }

  String _generateId(String number, DateTime timestamp) {
    final cleanNumber = number.replaceAll('+', '');
    final year = timestamp.year.toString().substring(2);
    final month = timestamp.month.toString().padLeft(2, '0');
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$cleanNumber$year$month$hour$minute';
  }

  String _mapType(CallType? t) {
    switch (t) {
      case CallType.incoming:
        return 'incoming';
      case CallType.outgoing:
        return 'outgoing';
      case CallType.missed:
        return 'missed';
      case CallType.voiceMail:
        return 'voicemail';
      case CallType.rejected:
        return 'rejected';
      case CallType.blocked:
        return 'blocked';
      case CallType.answeredExternally:
        return 'answered_externally';
      case CallType.wifiIncoming:
        return 'wifi_incoming';
      case CallType.wifiOutgoing:
        return 'wifi_outgoing';
      default:
        if (t != null) {
          return t.name;
        }
        return 'Phone_Call';
    }
  }

  Future<void> initializeCallStateListener() async {
    if (kIsWeb) {
      LoggerService.info('Call state listener skipped on Web');
      return;
    }
    
    try {
      // Initialize notifications
      await NotificationService.initialize();
      
      final callStateHandler = CallStateHandler();
      await callStateHandler.initialize();

      _callStateSubscription?.cancel();

      _callStateSubscription = callStateHandler.onCallStateChanged.listen(
        (call_state_models.CallState callState) {
          _isOnCallRealTime = callState.isCallActive;
          try {
            callActiveNotifier.value = _isOnCallRealTime;
          } catch (_) {}

          if (callState.isCallActive) {
            LoggerService.info('Real-time: Call active detected (type: ${callState.callType})');
            LoggerService.ui('Real-time: Call active detected (type: ${callState.callType})');
            NotificationService.showCallActiveNotification();
            
            // Cancel any pending sync timers
            _postCallSyncTimer?.cancel();
            _nextSyncTimer?.cancel();
          } else {
            LoggerService.info('Real-time: Call ended');
            LoggerService.ui('Real-time: Call ended');
            NotificationService.showCallEndedNotification();
            
            // Schedule post-call sync
            _schedulePostCallSync();
          }
        },
        onError: (error) {
          LoggerService.warn('Call state listener error: $error');
          _isOnCallRealTime = false;
        },
      );
      LoggerService.info('Real-time call state listener initialized');
    } catch (e) {
      LoggerService.warn('Failed to initialize call state listener: $e');
      _isOnCallRealTime = false;
    }
  }

  Future<void> disposeCallStateListener() async {
    if (kIsWeb) return;
    
    try {
      await CallStateHandler().dispose();
    } catch (e) {
      LoggerService.warn('Error disposing call state listener: $e');
    }
    _callStateSubscription?.cancel();
    _callStateSubscription = null;
    
    _postCallSyncTimer?.cancel();
    _nextSyncTimer?.cancel();
    
    _isOnCallRealTime = false;
    try {
      callActiveNotifier.value = false;
    } catch (_) {}
    
    await NotificationService.clearAllNotifications();
  }

  Future<bool> isOnCall({
    Duration activeWindow = const Duration(seconds: 3),
  }) async {
    if (kIsWeb) return false;

    if (_isOnCallRealTime) {
      return true;
    }

    try {
      final entries = await CallLog.get();
      if (entries.isEmpty) return false;

      final now = DateTime.now();
      final sortedEntries = entries.toList()
        ..sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));

      final mostRecent = sortedEntries.first;
      final callStart = DateTime.fromMillisecondsSinceEpoch(mostRecent.timestamp ?? 0);
      final duration = mostRecent.duration ?? 0;

      if (duration == 0) {
        final timeSinceStart = now.difference(callStart);
        if (timeSinceStart < const Duration(seconds: 10)) {
          return true;
        }
        return false;
      }

      final callEnd = callStart.add(Duration(seconds: duration));
      final timeSinceEnd = now.difference(callEnd);

      if (timeSinceEnd < activeWindow && timeSinceEnd >= Duration.zero) {
        return true;
      }

      return false;
    } catch (e) {
      LoggerService.warn('isOnCall check failed: $e');
    }
    return false;
  }
  
  void _schedulePostCallSync() {
    // Cancel any existing timers
    _postCallSyncTimer?.cancel();
    _nextSyncTimer?.cancel();
    
    // Schedule first sync after 5 seconds
    _postCallSyncTimer = Timer(const Duration(seconds: 5), () async {
      try {
        final newCount = await scanAndEnqueueNewCalls();
        if (newCount > 0) {
          LoggerService.info('Post-call sync found $newCount new calls');
          await performBackgroundSync();
          NotificationService.showSyncCompletedNotification(newCount);
        }
      } catch (e) {
        LoggerService.error('First post-call sync failed', e);
        NotificationService.showSyncErrorNotification(e.toString());
      }
    });
    
    // Schedule second sync after 1 minute to catch any delayed updates
    _nextSyncTimer = Timer(const Duration(minutes: 1), () async {
      try {
        final newCount = await scanAndEnqueueNewCalls();
        if (newCount > 0) {
          LoggerService.info('Second post-call sync found $newCount new calls');
          await performBackgroundSync();
          NotificationService.showSyncCompletedNotification(newCount);
        }
      } catch (e) {
        LoggerService.error('Second post-call sync failed', e);
        NotificationService.showSyncErrorNotification(e.toString());
      }
    });
  }

  static Future<void> performBackgroundSync() async {
    try {
      final syncSvc = SyncService(Supabase.instance.client);
      await syncSvc.syncPending();
    } catch (e) {
      LoggerService.error('Background sync failed', e);
      NotificationService.showSyncErrorNotification(e.toString());
    }
  }
}