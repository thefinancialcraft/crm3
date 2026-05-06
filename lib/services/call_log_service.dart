import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:call_log/call_log.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phone_state/phone_state.dart';

import '../models/call_log_model.dart';
import 'storage_service.dart';
import '../utils/device_utils.dart';
import 'package:permission_handler/permission_handler.dart';
import 'logger_service.dart';
import 'sync_service.dart';
import 'notification_service.dart';
import 'webbridge_service.dart';
import '../models/user_model.dart';
import '../utils/phone_utils.dart';
import 'background_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

/// Internal state machine for call tracking
enum CallTrackingState { idle, dialing, ringing, active }

class CallLogService {
  // Singleton pattern
  static final CallLogService _instance = CallLogService._internal();
  factory CallLogService() => _instance;
  CallLogService._internal();

  // Public Notifiers
  static final ValueNotifier<bool> callActiveNotifier = ValueNotifier<bool>(
    false,
  );
  static final ValueNotifier<String?> currentNumberNotifier =
      ValueNotifier<String?>(null);
  static final ValueNotifier<String?> customerNameNotifier =
      ValueNotifier<String?>(null);
  static final ValueNotifier<bool> isPersonalNotifier = ValueNotifier<bool>(
    true,
  );

  static const _nativeChannel = MethodChannel('com.example.crm3/main');

  static bool get isOnCallRealTime => callActiveNotifier.value;
  static String? get currentlyTrackedNumber => currentNumberNotifier.value;

  /// Places a direct call using native ACTION_CALL
  Future<void> placeDirectCall(String number) async {
    final simId = StorageService.getDefaultSim();
    final slotIndex = StorageService.getDefaultSimSlot();
    LoggerService.info("📞 CallLogService: placeDirectCall -> $number | SimId: $simId | Slot: $slotIndex");
    _currentNumber = number;
    currentNumberNotifier.value = number;
    WebBridgeService.notifyCallStatus("connecting", number);
    try {
      await _nativeChannel.invokeMethod('directCall', {
        'number': number,
        'simId': simId,
        'slotIndex': slotIndex,
      });
    } catch (e) {
      LoggerService.error("❌ Failed to place direct call for $number", e);
    }
  }

  /// Sets the current number manually (e.g. from Web Bridge)
  void setCurrentNumber(String? number) {
    if (number != null && number.isNotEmpty) {
      LoggerService.info(
        "📞 CallLogService: Manually setting current number to $number",
      );
      _currentNumber = number;
      currentNumberNotifier.value = number;
    }
  }

  /// Ends the active call programmatically
  Future<bool> disconnectCall() async {
    try {
      final bool ok = await _nativeChannel.invokeMethod('disconnectCall');
      return ok;
    } catch (e) {
      LoggerService.error("❌ Failed to disconnect call", e);
      return false;
    }
  }

  // Sync state flags
  static const String _firstSyncKey = 'is_first_sync';
  static const String _lastSyncTimeKey = 'last_sync_time';

  // --- INTERNAL STATE ---
  CallTrackingState _state = CallTrackingState.idle;
  String? _currentNumber;
  DateTime? _callStartTime;
  bool _isProcessingEnd = false;
  String? _detectedCallType;

  // 🛡️ OPTIMIZATION FLAGS (Double Hit Prevention)
  String? _lastSyncedNumber;
  bool? _lastSyncedOnCall;

  // 🌉 THE BRIDGE: Shared instance and stream subscription
  SyncService get _syncSvc => SyncService.instance;
  StreamSubscription<LiveCallResult>? _bridgeSubscription;

  // --- DEPENDENCIES & SUBSCRIPTIONS ---
  StreamSubscription? _liveCallSubscription;
  Timer? _autoSyncTimer;
  Timer? _postCallDebounceTimer;
  bool _isUserLoggedIn = false;
  bool _isScanInProgress = false; // 🚀 LOCK FOR SCANNING

  Future<void> initializeCallStateListener() async {
    if (kIsWeb) return;
    LoggerService.info('🚀 CallLogService: Initializing...');

    // 1. Permission check pehle
    final phoneGranted = await Permission.phone.isGranted;
    final callLogGranted = await _checkCallLogPermission();
    
    if (!phoneGranted) {
      LoggerService.warn('Phone permission denied — call detection disabled');
      // App crash mat karo, sirf feature disable karo
      _showPermissionRequiredDialog();
      return;
    }
    
    // Call log optional feature hai
    if (!callLogGranted) {
      LoggerService.warn('Call log permission denied — using live detection only');
      // scanAndEnqueueNewCalls() skip karo, sirf live detection chalao
    }

    await NotificationService.initialize();
    await _checkLoginStatus();
    _hardResetSession("Initialization");

    // 🌉 Start listening to the Bridge
    _startBridgeListening();
    _startLiveSubscription();
    LoggerService.info('✅ CallLogService: Initialized');
  }

  Future<bool> _checkCallLogPermission() async {
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        if (info.version.sdkInt >= 29) {
          // On Android 10+, READ_CALL_LOG is often required separately or bundled
          // If permission_handler doesn't have a specific callLog, we use a custom check or ignore
          return await Permission.phone.isGranted;
        }
      }
      return await Permission.phone.isGranted;
    } catch (_) {
      return false;
    }
  }

  void _showPermissionRequiredDialog() {
    // For background service, we just log. The UI should handle showing the dialog.
    LoggerService.warn('⚠️ CRM Feature Restricted: Phone permissions are missing.');
  }

  void _startBridgeListening() {
    _bridgeSubscription?.cancel();
    _bridgeSubscription = _syncSvc.liveUpdates.listen((data) {
      if (data.isOnCall) {
        _currentNumber = data.number;
        currentNumberNotifier.value = data.number;
        customerNameNotifier.value = data.name;
        isPersonalNotifier.value = data.isPersonal;

        _showOverlay(
          number: data.number,
          name: data.name,
          isPersonal: data.isPersonal,
          status: "Active",
        );
      }
    });
  }

  void disposeCallStateListener() {
    _bridgeSubscription?.cancel();
    _liveCallSubscription?.cancel();
    _autoSyncTimer?.cancel();
    _postCallDebounceTimer?.cancel();
    LoggerService.info('🛑 CallLogService: Disposed');
  }

  Future<void> _checkLoginStatus() async {
    final user = StorageService.getUser();
    _isUserLoggedIn = user != null;
    if (_isUserLoggedIn) {
      startAutoSync();
      // 🚀 Start command listener for existing session
      SyncService.instance.startCommandListener();
    }
  }

  Future<void> onUserLogin(Map<String, dynamic> payload) async {
    _isUserLoggedIn = true;
    _hardResetSession("Login");
    
    // 🛡️ Ensure central storage is updated
    await StorageService.setUserSession(payload);
    
    // Start Background Service if not running
    if (!kIsWeb) {
      await BackgroundService.setup();
    }
    
    await scanAndEnqueueNewCalls(); // Fetch all logs since app was last active
    startAutoSync();
    
    // Start Remote Command Listener
    await SyncService.instance.startCommandListener();
  }

  Future<void> onUserLogout() async {
    _isUserLoggedIn = false;
    _stopAutoSync();
    _hardResetSession("Logout");
    
    // 🛡️ CENTRAL STORAGE: Clear everything
    await StorageService.clearUserSession();

    // Stop Background Service
    if (!kIsWeb) {
      await BackgroundService.stop();
    }

    // Stop Remote Command Listener
    await SyncService.instance.stopCommandListener();
  }

  void _startLiveSubscription() {
    _liveCallSubscription?.cancel();
    _liveCallSubscription = PhoneState.stream.listen((event) {
      LoggerService.info(
        '📡 Raw PhoneState Event: ${event.status} | Number: ${event.number}',
      );
      _handleCallEvent(event.status, event.number);
    }, onError: (e) => LoggerService.error('❌ PhoneState Stream Error', e));
  }

  Future<void> _handleCallEvent(
    PhoneStateStatus status,
    String? rawNumber,
  ) async {
    String? finalNumber = rawNumber;

    // 🕵️ THE MASTER FALLBACK:
    // If number is missing from PhoneState (common in background/outgoing),
    // we use a tiered approach to recover it.
    if (finalNumber == null ||
        finalNumber == "Unknown" ||
        finalNumber.isEmpty) {
      // 0. Use currently tracked number if available (Best for Disconnects)
      if (_currentNumber != null &&
          _currentNumber!.isNotEmpty &&
          _currentNumber != "Unknown") {
        finalNumber = _currentNumber;
        LoggerService.info('✅ Using in-memory session number: $finalNumber');
      } else {
        // 1. Ask Native Kotlin Hub Directly (Most Reliable)
        try {
          finalNumber = await _nativeChannel.invokeMethod('getNativeNumber');
          if (finalNumber != null && finalNumber != "Unknown") {
            LoggerService.info('✅ Native recovered number: $finalNumber');
          }
        } catch (e) {
          LoggerService.error('Native number fetch failed', e);
        }

        // 2. Try SharedPrefs (Secondary Fallback)
        if (finalNumber == null ||
            finalNumber == "Unknown" ||
            finalNumber.isEmpty) {
          try {
            final prefs = await SharedPreferences.getInstance();
            finalNumber = prefs.getString('current_call_number');
            if (finalNumber != null) {
              LoggerService.info(
                '✅ SharedPrefs recovered number: $finalNumber',
              );
            }
          } catch (_) {}
        }
      }
    }

    if (finalNumber != null && finalNumber.isNotEmpty) {
      _currentNumber = finalNumber;
    }

    LoggerService.info('📞 Call Event: $status | Master Number: $finalNumber');

    switch (status) {
      case PhoneStateStatus.CALL_INCOMING:
        _detectedCallType = 'incoming';
        _lastSyncedNumber = null; // 🚀 FORCED RESET
        await _handleCallStart(finalNumber);
        break;
      case PhoneStateStatus.CALL_STARTED:
        _lastSyncedNumber = null; // 🚀 FORCED RESET
        if (_state == CallTrackingState.idle) {
          _detectedCallType = 'outgoing';
          await _handleCallActive(finalNumber);
        } else if (_state == CallTrackingState.ringing) {
          await _handleCallActive(finalNumber);
        }
        break;
      case PhoneStateStatus.CALL_ENDED:
        LoggerService.info('📞 Call Ended detected for: $finalNumber');
        await _handleCallEnd(finalNumber);
        break;
      default:
        LoggerService.info('📞 Untracked Phone State: $status');
        break;
    }
  }

  Future<void> _handleCallStart(String? rawNumber) async {
    _hardResetSession("New Incoming Call");
    _currentNumber = rawNumber;
    _state = CallTrackingState.ringing;
    _callStartTime = DateTime.now();

    // 🚀 INCOMING: Start sync/lookup now for Caller ID during Ringing
    LoggerService.info('📞 Notifying WebBridge: INCOMING -> ${_currentNumber ?? "Unknown"}');
    await _updateSyncMetaSafely(onCall: true, number: _currentNumber);
    WebBridgeService.notifyCallStatus("connecting", _currentNumber);

    // NotificationService.showCallNotification("📞 Incoming: $_currentNumber");
  }

  Future<void> _handleCallActive(String? rawNumber) async {
    if (_currentNumber == null && rawNumber != null) {
      _currentNumber = rawNumber;
    }

    final bool wasRinging = _state == CallTrackingState.ringing;
    _state = CallTrackingState.active;
    callActiveNotifier.value = true;

    // Set start time for outgoing call if not already set during ringing
    _callStartTime ??= DateTime.now();

    // NotificationService.showCallActiveNotification();

    // 🚀 SYNC LOGIC:
    // - Incoming: Already synced in _handleCallStart, _updateSyncMetaSafely will skip.
    // - Outgoing: First time hit, will sync now as dialing starts.
    await _updateSyncMetaSafely(onCall: true, number: _currentNumber);

    // Notify WebBridge
    if (wasRinging) {
      WebBridgeService.notifyCallStatus("connected", _currentNumber);
    } else {
      WebBridgeService.notifyCallStatus("connecting", _currentNumber);
    }
  }

  Future<void> _handleCallEnd(String? rawNumber) async {
    if (_isProcessingEnd) return;
    _isProcessingEnd = true;
    try {
      if (_currentNumber == null && rawNumber != null) {
        _currentNumber = rawNumber;
      }
      if (_currentNumber != null && _isUserLoggedIn) {
        // 1. Wait briefly for system call log to update
        await Future.delayed(const Duration(seconds: 2));

        final now = DateTime.now();
        DateTime finalTimestamp = now;
        
        // 2. Fetch actual talktime, TRUE start time, and Type from system logs
        int actualDuration = 0;
        String? finalType = _detectedCallType;
        
        try {
          final Iterable<CallLogEntry> entries = await CallLog.query(
            number: _currentNumber,
          );
          if (entries.isNotEmpty) {
            final entry = entries.first;
            actualDuration = entry.duration ?? 0;
            if (entry.timestamp != null) {
              finalTimestamp = DateTime.fromMillisecondsSinceEpoch(entry.timestamp!);
            }
            
            // 🛰️ Recover Call Type from System Log
            if (entry.callType != null) {
               final rawTypeStr = entry.callType.toString().split('.').last.toLowerCase();
               if (rawTypeStr.contains('incoming')) {
                 finalType = 'incoming';
               } else if (rawTypeStr.contains('outgoing')) {
                 finalType = 'outgoing';
               } else if (rawTypeStr.contains('missed') || rawTypeStr.contains('rejected') || rawTypeStr.contains('declined')) {
                 finalType = 'missed';
               } else {
                 finalType = rawTypeStr;
               }
            }

            LoggerService.info(
              '✅ System Log Match: Duration $actualDuration, StartTime $finalTimestamp, Type $finalType',
            );
          } else {
            actualDuration = _callStartTime != null
                ? now.difference(_callStartTime!).inSeconds
                : 0;
            finalTimestamp = _callStartTime ?? now;
            LoggerService.warn(
              '⚠️ Call log not found. Using estimated duration/time.',
            );
          }
        } catch (e) {
          LoggerService.error('❌ Failed to query system call log', e);
          actualDuration = _callStartTime != null
              ? now.difference(_callStartTime!).inSeconds
              : 0;
          finalTimestamp = _callStartTime ?? now;
        }

        // 🚀 BRIDGE CALL: Use the unified data to prevent duplicates and unknown types
        _syncSvc.logManualCall(
          number: _currentNumber!,
          callType: finalType ?? 'unknown',
          duration: actualDuration,
          timestamp: finalTimestamp,
        ).catchError((e) => LoggerService.error('❌ Background logManualCall failed', e));
        
        // Use debouncer instead of direct sync
        _syncSvc.scheduleSyncDebounced();
      }
      await _updateSyncMetaSafely(onCall: false);
      // NotificationService.showCallEndedNotification();

      // Notify WebApp that the call ended
      LoggerService.info(
        "📞 CallLogService: Notifying WebBridge of ended call: $_currentNumber",
      );
      WebBridgeService.notifyCallEnded(_currentNumber);
    } finally {
      callActiveNotifier.value = false;
      _hardResetSession("End Complete");
    }
  }

  Future<void> _updateSyncMetaSafely({
    required bool onCall,
    String? number,
  }) async {
    if (!_isUserLoggedIn) return;

    // 🛡️ PREVENT REDUNDANCY
    if (_lastSyncedNumber == number &&
        _lastSyncedOnCall == onCall &&
        number != null) {
      return;
    }

    try {
      _lastSyncedNumber = number;
      _lastSyncedOnCall = onCall;

      // 🚀 BRIDGE: Just trigger the sync. Data will come back via the Bridge Stream.
      final result = await _syncSvc.updateLiveCallStatus(
        isOnCall: onCall,
        number: number ?? _currentNumber,
        callType: _detectedCallType,
      );

      // 🌉 COMMAND-DRIVEN OVERLAY:
      // Background isolate finishes lookup and THEN tells native to show the overlay.
      if (onCall) {
        try {
          if (!await Permission.systemAlertWindow.isGranted) return;
          
          // Use result if available, otherwise show a generic loading overlay
          final Map<String, dynamic> overlayData = result ?? {
            'number': number ?? _currentNumber ?? "Unknown",
            'name': "Searching...",
            'isPersonal': true,
            'status': _detectedCallType ?? "Active",
          };

          await _nativeChannel.invokeMethod(
            'showOverlayWithData',
            Map<String, dynamic>.from(overlayData),
          );
          LoggerService.info(
            '🚀 Command sent: showOverlayWithData (Force Trigger)',
          );
        } catch (e) {
          LoggerService.error('❌ Failed to trigger overlay display', e);
        }
      }
    } catch (e) {
      LoggerService.error('❌ SyncMeta error', e);
    }
  }

  void _hardResetSession(String reason) {
    _state = CallTrackingState.idle;
    _currentNumber = null;
    _detectedCallType = null;
    _callStartTime = null;
    _isProcessingEnd = false;
    _lastSyncedNumber = null;
    _lastSyncedOnCall = null;
    currentNumberNotifier.value = null;
    customerNameNotifier.value = null;
    isPersonalNotifier.value = true;
    _closeOverlay();
  }

  // --- SYNC METHODS ---
  void startAutoSync({Duration interval = const Duration(minutes: 30)}) {
    if (!_isUserLoggedIn) return;
    _autoSyncTimer?.cancel();
     _autoSyncTimer = Timer.periodic(interval, (timer) {
      if (_state == CallTrackingState.idle) {
        scanAndEnqueueNewCalls();
        // Direct sync mat karo — debouncer handle karega
      }
    });
    // Startup pe ek baar
    scanAndEnqueueNewCalls();
  }

  void _stopAutoSync() => _autoSyncTimer?.cancel();

  static Future<void> performBackgroundSync({bool isAuto = false}) async {
    try {
      _instance._syncSvc.scheduleSyncDebounced(delay: Duration.zero);
    } catch (e) {
      LoggerService.error('❌ Sync failed', e);
    }
  }

  static Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_lastSyncTimeKey);
    return ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null;
  }

  static Future<void> updateLastSync(String val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSyncTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<bool> isFirstSyncCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_firstSyncKey) ?? false;
  }

  static Future<void> markFirstSyncCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstSyncKey, true);
  }

  Future<bool> sendFakeData() async {
    if (kIsWeb) return false;
    try {
      final currentDeviceId = await DeviceUtils.getDeviceId();
      final ts = DateTime.now().subtract(const Duration(minutes: 5));
      final id = 'fake_${ts.millisecondsSinceEpoch}';

      final userMap = StorageService.getUser();
      final user = userMap != null ? UserModel.fromJson(userMap) : null;

      final model = CallLogModel(
        id: id,
        number: '1234567890',
        name: 'John Doe (Fake)',
        callType: 'incoming',
        duration: 45,
        timestamp: ts.toUtc(),
        deviceId: currentDeviceId,
        employeeId: user?.employeeId ?? 'fake_emp',
        userName: user?.userName ?? 'Fake User',
        organizationId: user?.organizationId ?? 'fake_org',
        idx: id,
      );

      await StorageService.callBucket.put(id, {
        'model': model.toJson(),
        'status': 'pending',
      });
      return true;
    } catch (e) {
      LoggerService.error('Error sending fake data', e);
      return false;
    }
  }

  void testOverlay() {
    _showOverlay(
      number: "123-456-7890",
      name: "Test Customer",
      isPersonal: false,
      status: "Testing",
    );
  }

  // --- OVERLAY ---
  Future<void> _showOverlay({
    String? number,
    String? name,
    bool? isPersonal,
    String? status,
  }) async {
    if (kIsWeb) return;
    try {
      // 🛡️ CHECK PERMISSION BEFORE SHOWING
      if (!await Permission.systemAlertWindow.isGranted) {
        LoggerService.info('🪟 Overlay skipped: Permission not granted');
        return;
      }

      // We use our custom native overlay instead of the package
      // to have better control over height and interaction.
      await _nativeChannel.invokeMethod('showOverlayWithData', {
        'number': number,
        'name': name,
        'isPersonal': isPersonal ?? true,
        'status': status ?? "Active",
      });
      LoggerService.info('🚀 Triggered custom native overlay');
    } catch (e) {
      LoggerService.error('Error showing overlay', e);
    }
  }

  Future<void> _closeOverlay() async {
    try {
      if (!kIsWeb) {
        await _nativeChannel.invokeMethod('closeOverlay');
      }
    } catch (e) {
      LoggerService.error('Error closing overlay', e);
    }
  }

  /// Scans all system call logs and enqueues unsynced ones in a non-blocking way
  Future<void> scanAndEnqueueNewCalls() async {
    if (!_isUserLoggedIn) return;
    if (_isScanInProgress) return; // 🚀 Double scan prevent
    _isScanInProgress = true;

    try {
      // 🛡️ Permission Check
      if (!await Permission.phone.isGranted) {
        LoggerService.warn('🔍 Scan skipped: Permission denied');
        return;
      }
      
      LoggerService.info('🔍 CallLogService: Triggering background scan...');

      // ✅ FIX: Await this delayed future correctly
      await Future.delayed(const Duration(milliseconds: 500));

      var lastScanned = StorageService.getLastScannedAt();
      if (lastScanned == null) {
        final nowTs = DateTime.now().millisecondsSinceEpoch;
        LoggerService.info('🆕 Fresh Install. Setting pointer to $nowTs');
        await StorageService.setLastScannedAt(nowTs);
        return;
      }

      final allEntries = await CallLog.query(dateFrom: lastScanned);
      final entries = allEntries.toList().reversed.take(50).toList();
      if (entries.isEmpty) return;

      final deviceId = await DeviceUtils.getDeviceId();
      final userMap = StorageService.getUser();
      final user = userMap != null ? UserModel.fromJson(userMap) : null;

      int enqueued = 0;
      int maxTs = lastScanned;

      for (var entry in entries) {
        if (enqueued % 10 == 0) {
          await Future.delayed(const Duration(milliseconds: 5));
        }

        final number = entry.number ?? '';
        final timestamp = entry.timestamp ?? 0;
        final duration = entry.duration ?? 0;
        if (number.isEmpty) continue;

        final cleanNumber = PhoneUtils.normalize(number);
        final id = '${cleanNumber}_${timestamp}_$duration';

        if (StorageService.syncedBucket.containsKey(id) ||
            StorageService.callBucket.containsKey(id)) {
          continue;
        }

        final model = CallLogModel(
          id: id,
          number: cleanNumber,
          callType: _mapCallType(entry.callType),
          duration: duration,
          timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp).toUtc(),
          deviceId: deviceId,
          employeeId: user?.employeeId ?? 'unknown',
          userName: user?.userName,
          organizationId: user?.organizationId,
          isPersonal: true, // Default true, sync_service will classify properly
          idx: id,
        );

        await StorageService.callBucket.put(id, {
          'model': model.toJson(),
          'status': 'pending',
          'attempts': 0,
        });
        enqueued++;
        if (timestamp > maxTs) maxTs = timestamp;
      }

      if (enqueued > 0) {
        await StorageService.setLastScannedAt(maxTs);
        LoggerService.info('✅ Scan enqueued $enqueued calls');
        _syncSvc.scheduleSyncDebounced(delay: const Duration(seconds: 5));
      }
    } catch (e) {
      LoggerService.error('Scan failed', e);
    } finally {
      _isScanInProgress = false;
    }
  }

  String _mapCallType(dynamic rawType) {
    if (rawType == null) return 'unknown';
    final typeStr = rawType.toString().split('.').last.toLowerCase();
    if (typeStr.contains('incoming')) return 'incoming';
    if (typeStr.contains('outgoing')) return 'outgoing';
    if (typeStr.contains('missed') || typeStr.contains('rejected')) return 'missed';
    if (typeStr.contains('blocked')) return 'blocked';
    return typeStr;
  }

  /// Specialized method to enqueue specific logs (used by UI triggers)
  Future<void> enqueueUntrackedLogs(List<CallLogEntry> logs) async {
    if (!_isUserLoggedIn) return;
    
    int enqueued = 0;
    final deviceId = await DeviceUtils.getDeviceId();
    final userMap = StorageService.getUser();
    final user = userMap != null ? UserModel.fromJson(userMap) : null;

    for (var entry in logs) {
      final number = entry.number ?? '';
      final timestamp = entry.timestamp ?? 0;
      final duration = entry.duration ?? 0;
      if (number.isEmpty) continue;

      final cleanNumber = PhoneUtils.normalize(number);
      final id = '${cleanNumber}_${timestamp}_$duration';

      if (!StorageService.syncedBucket.containsKey(id) && !StorageService.callBucket.containsKey(id)) {
        // 🛰️ CALL TYPE MAPPING (Handling WiFi and Special OS Types)
        String cType = 'unknown';
        final rawType = entry.callType;
        if (rawType != null) {
          cType = rawType.toString().split('.').last.toLowerCase();
          if (cType == 'wifi_incoming' || cType.contains('wifi')) {
            cType = 'incoming';
          } else if (cType == 'wifi_outgoing') {
            cType = 'outgoing';
          }
        }

        final model = CallLogModel(
          id: id,
          number: cleanNumber,
          name: entry.name,
          callType: cType,
          duration: duration,
          timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp).toUtc(),
          deviceId: deviceId,
          employeeId: user?.employeeId ?? 'unknown',
          userName: user?.userName,
          organizationId: user?.organizationId,
          isPersonal: await _syncSvc.isNumberPersonal(cleanNumber),
          idx: id,
        );

        await StorageService.callBucket.put(id, {
          'model': model.toJson(),
          'status': 'pending',
          'attempts': 0,
        });
        enqueued++;
      }
    }

    if (enqueued > 0) {
      LoggerService.info('✅ CallLogPage trigger enqueued $enqueued untracked calls');
      SyncService.instance.syncPending();
    }
  }
}
