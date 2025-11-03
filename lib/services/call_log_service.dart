import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:call_log/call_log.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:call_state_handler/call_state_handler.dart';
import 'package:call_state_handler/models/call_state.dart' as call_state_models;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/call_log_model.dart';
import 'storage_service.dart';
import '../utils/device_utils.dart';
import 'logger_service.dart';
import 'sync_service.dart';

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
  StreamSubscription? _backgroundCallStateSubscription;
  FlutterLocalNotificationsPlugin? _notificationsPlugin;
  Timer? _postCallSyncTimer;
  Timer? _nextSyncTimer;

  /// Constructor that keeps track of the singleton instance
  CallLogService() {
    _instance = this;
  }
  
  /// Get the timestamp of last successful sync
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

  /// Save the timestamp and ID of last successful sync
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

  /// Getter for real-time call state from the singleton instance
  static bool get isOnCallRealTime => _instance?._isOnCallRealTime ?? false;

  /// Check if first sync has been completed
  static Future<bool> isFirstSyncCompleted() async {
    if (kIsWeb) return true; // Skip on web
    
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_firstSyncKey) ?? false;
    } catch (e) {
      LoggerService.warn('Failed to check first sync status: $e');
      return false;
    }
  }

  /// Mark first sync as completed
  static Future<void> markFirstSyncCompleted() async {
    if (kIsWeb) return; // Skip on web
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_firstSyncKey, true);
      LoggerService.info('First sync marked as completed');
    } catch (e) {
      LoggerService.warn('Failed to mark first sync as completed: $e');
    }
  }

  /// No longer performs auto sync - only handles manual sync requests
  void startAutoSync({
    Duration interval = const Duration(minutes: 1),
    Function(int pending, int synced)? onProgress,
  }) {
    // Auto sync is disabled
    LoggerService.info('Auto sync is disabled - use manual sync after call ends');
  }

  /// Enqueue a few fake call log entries into the local callBucket for testing.
  /// Returns true when entries were added.
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
          'timestamp': now
              .subtract(const Duration(minutes: 5))
              .toIso8601String(),
        },
        {
          'number': '+10000000002',
          'name': 'Fake Two',
          'call_type': 'outgoing',
          'duration': 34,
          'timestamp': now
              .subtract(const Duration(minutes: 10))
              .toIso8601String(),
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

  /// Scans device call logs and enqueues new entries.
  /// Returns the number of new entries enqueued.
  /// Scans device call logs and enqueues new entries.
  ///
  /// If [dateFrom] is provided, only entries after that DateTime will be
  /// considered. If not provided, the method will use the last successful
  /// sync time (from shared preferences) when available; otherwise it will
  /// default to the last 3 days. This makes first-run behavior only pick
  /// up the last 3 days while subsequent runs pick up new calls since the
  /// last sync.
  Future<int> scanAndEnqueueNewCalls({DateTime? dateFrom}) async {
    if (kIsWeb) {
      LoggerService.info(
        'CallLogService.scanAndEnqueueNewCalls skipped on Web',
      );
      return 0;
    }

    LoggerService.info('CallLogService.scanAndEnqueueNewCalls started');
    try {
      // Determine cutoff: use provided dateFrom, or last sync time, or last 3 days
      final lastSync = dateFrom ?? await CallLogService.getLastSyncTime();
      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
      final cutoff = lastSync ?? threeDaysAgo;

      // First, fetch existing calls from Supabase for this device
      final currentDeviceId = await DeviceUtils.getDeviceId();
      final supabase = Supabase.instance.client;
      
      LoggerService.info('Fetching existing calls from Supabase since ${cutoff.toIso8601String()}');
      final existingCalls = await supabase
          .from('call_logs')
          .select('number,timestamp,duration,call_type')
          .eq('device_id', currentDeviceId)
          .gte('timestamp', cutoff.toIso8601String());
      
      // Create lookup set for quick duplicate checking
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

      // Get recent calls and filter them
      final Iterable<CallLogEntry> entries = await CallLog.get();
      
      // Filter entries newer than cutoff
      final filteredEntries = entries.where((e) {
        final ts = DateTime.fromMillisecondsSinceEpoch(e.timestamp ?? 0);
        return ts.isAfter(cutoff);
      }).toList();
      LoggerService.info('Found ${filteredEntries.length} entries newer than ${cutoff.toUtc().toIso8601String()}');
      var added = 0;
      for (final e in filteredEntries) {
        final ts = DateTime.fromMillisecondsSinceEpoch(e.timestamp ?? 0);
        final id = _generateId(e.number ?? '', ts);
        
        // Check duplicates in local storage first
        final existingInSync = StorageService.syncedBucket.get(id);
        final existingInPending = StorageService.callBucket.get(id);
        final isLocalDuplicate = existingInSync != null || existingInPending != null;
        
        if (!isLocalDuplicate) {
          // Then check in Supabase data
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
      LoggerService.info(
        'CallLogService.scanAndEnqueueNewCalls completed; added=$added',
      );
      return added;
    } catch (e) {
      LoggerService.error('CallLogService.scanAndEnqueueNewCalls failed: $e');
      return 0;
    }
  }

  /// Generates a compact ID: phone (without +) + last2year + month + hour + minute
  /// Example: "+911144019847_2025-10-17T20:32:51.059" -> "91114401984725102032"
  String _generateId(String number, DateTime timestamp) {
    // Remove + sign from phone number
    final cleanNumber = number.replaceAll('+', '');
    // Extract year (last 2 digits), month, hour, minute
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
        // For unknown types, use the enum name if available, otherwise 'Phone_Call'
        if (t != null) {
          return t.name;
        }
        return 'Phone_Call';
    }
  }

  /// Initialize real-time call state listener (like Truecaller)
  /// This detects calls as soon as dial button is pressed
  Future<void> initializeCallStateListener() async {
    if (kIsWeb) {
      LoggerService.info('Call state listener skipped on Web');
      return;
    }
    
    try {
      // Initialize notifications first
      if (_notificationsPlugin == null) {
        _notificationsPlugin = FlutterLocalNotificationsPlugin();
        await _notificationsPlugin!.initialize(
          const InitializationSettings(
            android: AndroidInitializationSettings('ic_bg_service_small'),
          ),
        );
        
        // Create notification channel
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          'call_log_sync_channel',
          'Call Log Service',
          description: 'Monitors and syncs call logs',
          importance: Importance.high,
        );
        
        await _notificationsPlugin!
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
      }
      
      final callStateHandler = CallStateHandler();
      // Initialize the call detector
      await callStateHandler.initialize();

      // Cancel any existing subscription
      _callStateSubscription?.cancel();

      // Listen to call state changes
      _callStateSubscription = callStateHandler.onCallStateChanged.listen(
        (call_state_models.CallState callState) {
          // Update real-time call status based on isCallActive
          _isOnCallRealTime = callState.isCallActive;
          // notify UI listeners
          try {
            callActiveNotifier.value = _isOnCallRealTime;
          } catch (_) {}

          if (callState.isCallActive) {
            LoggerService.info(
              'Real-time: Call active detected (type: ${callState.callType})',
            );
            LoggerService.ui('Real-time: Call active detected (type: ${callState.callType})');
            // Show notification for active call (include type)
            _showCallNotification('Call is active', 'Call type: ${callState.callType}');
          } else {
            LoggerService.info('Real-time: Call ended');
            LoggerService.ui('Real-time: Call ended');
            // Show notification for call ended
            _showCallNotification('Call ended', 'Starting sync...');
            // Schedule a sync after call ends
            Future.delayed(const Duration(seconds: 5), () {
              _performPostCallSync();
            });
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
  
  /// Initialize call state listener for background service
  Future<void> initializeBackgroundCallStateListener(FlutterLocalNotificationsPlugin notificationsPlugin) async {
    if (kIsWeb) {
      LoggerService.info('Background call state listener skipped on Web');
      return;
    }
    
    _notificationsPlugin = notificationsPlugin;
    
    try {
      final callStateHandler = CallStateHandler();

      // Initialize the call detector
      await callStateHandler.initialize();

      // Cancel any existing subscription
      _backgroundCallStateSubscription?.cancel();

      // Listen to call state changes
      _backgroundCallStateSubscription = callStateHandler.onCallStateChanged.listen(
        (call_state_models.CallState callState) {
          // Update real-time call status based on isCallActive
          _isOnCallRealTime = callState.isCallActive;
          // notify UI listeners
          try {
            callActiveNotifier.value = _isOnCallRealTime;
          } catch (_) {}

          if (callState.isCallActive) {
            LoggerService.info(
              'Background: Call active detected (type: ${callState.callType})',
            );
            LoggerService.ui('Background: Call active detected (type: ${callState.callType})');
            // Show notification for active call
            _showBackgroundCallNotification('Call Active', 'Current call: ${callState.callType}');
            
            // Cancel any scheduled sync timers when a call starts
            _postCallSyncTimer?.cancel();
            _nextSyncTimer?.cancel();
            _postCallSyncTimer = null;
            _nextSyncTimer = null;
            LoggerService.info('Cancelled scheduled sync timers due to active call');
          } else {
            LoggerService.info('Background: Call ended');
            LoggerService.ui('Background: Call ended');
            
            // Clear the active call notification immediately
            _clearBackgroundCallNotification();
            
            // Small delay to ensure call log is updated
            _postCallSyncTimer = Timer(const Duration(seconds: 5), () async {
              // First scan for new calls
              final newCount = await scanAndEnqueueNewCalls();
              if (newCount > 0) {
                // Perform sync silently without notification
                await performBackgroundSync();
                LoggerService.info('Post-call sync completed');
              } else {
                LoggerService.info('No new calls to sync');
              }
            });
          }
        },
        onError: (error) {
          LoggerService.warn('Background call state listener error: $error');
          _isOnCallRealTime = false;
        },
      );
      LoggerService.info('Background call state listener initialized');
    } catch (e) {
      LoggerService.warn('Failed to initialize background call state listener: $e');
      _isOnCallRealTime = false;
    }
  }

  /// Dispose call state listener
  Future<void> disposeCallStateListener() async {
    if (kIsWeb) return;
    
    try {
      await CallStateHandler().dispose();
    } catch (e) {
      LoggerService.warn('Error disposing call state listener: $e');
    }
    _callStateSubscription?.cancel();
    _callStateSubscription = null;
    _backgroundCallStateSubscription?.cancel();
    _backgroundCallStateSubscription = null;
    
    // Cancel sync timers
    _postCallSyncTimer?.cancel();
    _nextSyncTimer?.cancel();
    _postCallSyncTimer = null;
    _nextSyncTimer = null;
    
    _isOnCallRealTime = false;
    try {
      callActiveNotifier.value = false;
    } catch (_) {}
  }

  /// Detects if user is currently on an active call.
  /// Uses real-time call state listener (primary) and call logs (fallback)
  /// Real-time detection works like Truecaller - detects as soon as dial button is pressed
  Future<bool> isOnCall({
    Duration activeWindow = const Duration(seconds: 3),
  }) async {
    if (kIsWeb) return false;

    // First check real-time call state (most accurate)
    if (_isOnCallRealTime) {
      return true;
    }

    // Fallback: Check call logs if real-time listener not available or failed
    try {
      final entries = await CallLog.get();
      if (entries.isEmpty) return false;

      final now = DateTime.now();

      // Sort by most recent first
      final sortedEntries = entries.toList()
        ..sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));

      final mostRecent = sortedEntries.first;
      final callStart = DateTime.fromMillisecondsSinceEpoch(
        mostRecent.timestamp ?? 0,
      );
      final duration = mostRecent.duration ?? 0;

      // If duration is 0, call is likely still active (entry being updated in real-time)
      // Check if this entry is very recent (within last 10 seconds)
      if (duration == 0) {
        final timeSinceStart = now.difference(callStart);
        if (timeSinceStart < const Duration(seconds: 10)) {
          return true; // Active call, entry is being updated
        }
        return false;
      }

      // Call has ended - calculate when it ended (works for calls of any duration)
      // For example: call started 1 hour ago, duration 3600s, ended just now
      final callEnd = callStart.add(Duration(seconds: duration));
      final timeSinceEnd = now.difference(callEnd);

      // If call ended very recently (within active window), show as "on call"
      // This handles the delay when call log entry is registered after call ends
      // Works correctly even if call was very long (e.g., 1 hour)
      if (timeSinceEnd < activeWindow && timeSinceEnd >= Duration.zero) {
        return true; // Just ended, still showing as on call
      }

      // Call ended more than activeWindow ago, show as idle
      return false;
    } catch (e) {
      LoggerService.warn('isOnCall check failed: $e');
    }
    return false;
  }
  
  /// Public method to allow external access to scan and sync
  /// This can be called from background services
  static Future<void> performBackgroundSync() async {
    try {
      final callSvc = CallLogService();
      final newCount = await callSvc.scanAndEnqueueNewCalls();
      
      if (newCount > 0) {
        LoggerService.info('Background sync found $newCount new calls');
        final syncSvc = SyncService(Supabase.instance.client);
        
        // Get all pending entries sorted by timestamp
        final keys = StorageService.callBucket.keys.toList();
        final pending = keys.map((key) {
          final value = StorageService.callBucket.get(key);
          return MapEntry(key, value as Map<dynamic, dynamic>);
        }).where((e) => e.value['status'] == 'pending')
        .toList()
          ..sort((a, b) {
            final aTime = DateTime.parse((a.value['model'] as Map)['timestamp'] as String);
            final bTime = DateTime.parse((b.value['model'] as Map)['timestamp'] as String);
            return aTime.compareTo(bTime); // Oldest first
          });
        
        // Process one by one with retry mechanism
        for (final entry in pending) {
          final callId = entry.key;
          final attempts = entry.value['attempts'] as int? ?? 0;
          
          if (attempts >= _maxRetryAttempts) {
            LoggerService.warn('Skipping call $callId after $_maxRetryAttempts failed attempts');
            continue;
          }
          
          try {
            // Try to sync this specific call
            await syncSvc.syncSpecificCall(callId);
            // Update last sync info on success
            await updateLastSync(callId);
            LoggerService.info('Successfully synced call: $callId');
          } catch (e) {
            // Update attempt count and save error
            entry.value['attempts'] = attempts + 1;
            entry.value['lastError'] = e.toString();
            StorageService.callBucket.put(callId, entry.value);
            LoggerService.error('Failed to sync call $callId (attempt ${attempts + 1}): $e');
            
            // If not a duplicate error, wait a bit before next attempt
            if (!e.toString().contains('duplicate key value violates unique constraint')) {
              await Future.delayed(const Duration(seconds: 2));
            }
          }
        }
        
        LoggerService.info('Background sync completed');
      } else {
        LoggerService.info('Background sync found no new calls');
      }
    } catch (e, st) {
      LoggerService.error('Background sync failed', e, st);
    }
  }
  
  /// Show notification for active call
  void _showCallNotification(String title, String content) {
    // Use same notification function for both foreground and background
    _showBackgroundCallNotification(title, content);
    LoggerService.info('Call notification: $title - $content');
  }
  
  /// Show notification for active call in background
  void _showBackgroundCallNotification(String title, String content) {
    if (_notificationsPlugin != null) {
      _notificationsPlugin!.show(
        1002, // Use a different notification ID than BackgroundService
        title,
        content,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'call_log_sync_channel', // Use the same channel ID as BackgroundService
            'Call Log Service',
            icon: 'ic_bg_service_small',
            ongoing: false, // Don't make notifications persistent
            priority: Priority.high,
          ),
        ),
      );
    }
  }
  
  /// Clear background call notification
  void _clearBackgroundCallNotification() {
    if (_notificationsPlugin != null) {
      // Cancel the notification instead of showing monitoring message
      _notificationsPlugin!.cancel(1002);
    }
  }
  
  /// Perform sync after call ends
  Future<void> _performPostCallSync() async {
    try {
      final newCount = await scanAndEnqueueNewCalls();
      if (newCount > 0) {
        LoggerService.info('Post-call sync found $newCount new calls');
        final syncSvc = SyncService(Supabase.instance.client);
        await syncSvc.syncPending();
        LoggerService.info('Post-call sync completed');
      }
    } catch (e, st) {
      LoggerService.error('Post-call sync failed', e, st);
    }
  }
}