import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:call_log/call_log.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phone_state/phone_state.dart';

import '../models/call_log_model.dart';
import 'storage_service.dart';
import '../utils/device_utils.dart';
import 'logger_service.dart';
import 'sync_service.dart';
import 'notification_service.dart';

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

  static const _nativeChannel = MethodChannel('com.example.crm3/overlay');

  static bool get isOnCallRealTime => callActiveNotifier.value;

  // Sync state flags
  static const String _firstSyncKey = 'is_first_sync';
  static const String _lastSyncTimeKey = 'last_sync_time';

  // --- INTERNAL HELPERS ---
  Future<String?> _getLatestCallLogNumber() async {
    try {
      final Iterable<CallLogEntry> entries = await CallLog.get();
      if (entries.isNotEmpty) {
        return entries.first.number;
      }
    } catch (e) {
      LoggerService.error('Error fetching latest call log', e);
    }
    return null;
  }

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
  late final SyncService _syncSvc;
  StreamSubscription<LiveCallResult>? _bridgeSubscription;

  // --- DEPENDENCIES & SUBSCRIPTIONS ---
  StreamSubscription? _liveCallSubscription;
  Timer? _autoSyncTimer;
  Timer? _postCallDebounceTimer;
  bool _isUserLoggedIn = false;

  Future<void> initializeCallStateListener() async {
    if (kIsWeb) return;
    LoggerService.info('🚀 CallLogService: Initializing...');

    // Initialize the Bridge
    _syncSvc = SyncService(Supabase.instance.client);

    await NotificationService.initialize();
    await _checkLoginStatus();
    _hardResetSession("Initialization");

    // 🌉 Start listening to the Bridge
    _startBridgeListening();
    _startLiveSubscription();
    LoggerService.info('✅ CallLogService: Initialized');
  }

  void _startBridgeListening() {
    _bridgeSubscription?.cancel();
    _bridgeSubscription = _syncSvc.liveUpdates.listen((data) {
      if (data.isOnCall) {
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
    final session = Supabase.instance.client.auth.currentSession;
    _isUserLoggedIn = session != null;
  }

  Future<void> onUserLogin() async {
    _isUserLoggedIn = true;
    _hardResetSession("Login");
    startAutoSync();
  }

  Future<void> onUserLogout() async {
    _isUserLoggedIn = false;
    _stopAutoSync();
    _hardResetSession("Logout");
  }

  void _startLiveSubscription() {
    _liveCallSubscription?.cancel();
    _liveCallSubscription = PhoneState.stream.listen(
      (event) => _handleCallEvent(event.status, event.number),
      onError: (e) => LoggerService.error('❌ Stream Error', e),
    );
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
      // 1. Ask Native Kotlin Hub Directly (Most Reliable)
      try {
        finalNumber = await _nativeChannel.invokeMethod('getNativeNumber');
        LoggerService.info('✅ Native recovered number: $finalNumber');
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
        } catch (_) {}
      }

      // 3. Try System Call Log (Final Attempt)
      if (finalNumber == null ||
          finalNumber == "Unknown" ||
          finalNumber.isEmpty) {
        finalNumber = await _getLatestCallLogNumber();
      }
    }

    if (finalNumber != null && finalNumber.isNotEmpty) {
      _currentNumber = finalNumber;
    }

    LoggerService.info('📞 Call Event: $status | Master Number: $finalNumber');

    switch (status) {
      case PhoneStateStatus.CALL_INCOMING:
        _detectedCallType = 'incoming';
        await _handleCallStart(finalNumber);
        break;
      case PhoneStateStatus.CALL_STARTED:
        if (_state == CallTrackingState.idle) {
          _detectedCallType = 'outgoing';
          await _handleCallActive(finalNumber);
        } else if (_state == CallTrackingState.ringing) {
          await _handleCallActive(finalNumber);
        }
        break;
      case PhoneStateStatus.CALL_ENDED:
        await _handleCallEnd(finalNumber);
        break;
      default:
        break;
    }
  }

  Future<void> _handleCallStart(String? rawNumber) async {
    _hardResetSession("New Incoming Call");
    _currentNumber = rawNumber;
    _state = CallTrackingState.ringing;
    _callStartTime = DateTime.now();

    // 🚀 INCOMING: Start sync/lookup now for Caller ID during Ringing
    if (_currentNumber != null) {
      await _updateSyncMetaSafely(onCall: true, number: _currentNumber);
    }

    NotificationService.showCallNotification("📞 Incoming: $_currentNumber");
  }

  Future<void> _handleCallActive(String? rawNumber) async {
    if (_currentNumber == null && rawNumber != null) {
      _currentNumber = rawNumber;
    }
    _state = CallTrackingState.active;
    callActiveNotifier.value = true;

    // Set start time for outgoing call if not already set during ringing
    _callStartTime ??= DateTime.now();

    NotificationService.showCallActiveNotification();

    // 🚀 SYNC LOGIC:
    // - Incoming: Already synced in _handleCallStart, _updateSyncMetaSafely will skip.
    // - Outgoing: First time hit, will sync now as dialing starts.
    await _updateSyncMetaSafely(onCall: true, number: _currentNumber);
  }

  Future<void> _handleCallEnd(String? rawNumber) async {
    if (_isProcessingEnd) return;
    _isProcessingEnd = true;
    try {
      if (_currentNumber == null && rawNumber != null) {
        _currentNumber = rawNumber;
      }
      if (_currentNumber != null && _isUserLoggedIn) {
        final duration = _callStartTime != null
            ? DateTime.now().difference(_callStartTime!).inSeconds
            : 0;
        final now = DateTime.now();

        // 🚀 BRIDGE CALL: Messenger sends the signal
        await _syncSvc.logManualCall(
          number: _currentNumber!,
          callType: _detectedCallType ?? 'unknown',
          duration: duration,
          timestamp: now,
        );
      }
      await _updateSyncMetaSafely(onCall: false);
      NotificationService.showCallEndedNotification();
      _schedulePostCallEnrichment();
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
      if (onCall && result != null) {
        try {
          // If it's a start of a call, use 'showOverlayWithData' to trigger display
          // If it was already on, this will just update the data.
          await _nativeChannel.invokeMethod(
            'showOverlayWithData',
            Map<String, dynamic>.from(result),
          );
          LoggerService.info(
            '🚀 Command sent: showOverlayWithData _from_background',
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
  void startAutoSync({Duration interval = const Duration(minutes: 15)}) {
    if (!_isUserLoggedIn) return;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(interval, (timer) {
      if (_state == CallTrackingState.idle) performBackgroundSync(isAuto: true);
    });
    performBackgroundSync(isAuto: true);
  }

  void _stopAutoSync() => _autoSyncTimer?.cancel();

  void _schedulePostCallEnrichment() {
    _postCallDebounceTimer?.cancel();
    _postCallDebounceTimer = Timer(const Duration(minutes: 1), () {
      if (_state == CallTrackingState.idle && _isUserLoggedIn) {
        performBackgroundSync(isAuto: true, enrichFromSystemLogs: true);
      }
    });
  }

  static Future<void> performBackgroundSync({
    bool isAuto = false,
    bool enrichFromSystemLogs = false,
  }) async {
    try {
      if (enrichFromSystemLogs && !kIsWeb) {
        await _instance.scanAndEnqueueNewCalls();
      }
      await _instance._syncSvc.syncPending();
    } catch (e) {
      LoggerService.error('❌ Sync failed', e);
    }
  }

  Future<int> scanAndEnqueueNewCalls({DateTime? dateFrom}) async {
    if (kIsWeb) return 0;
    try {
      final currentDeviceId = await DeviceUtils.getDeviceId();

      // 1. Check Supabase for last sync info to avoid redundant scanning
      DateTime? cutoff;
      String? lastSyncedCallId;
      final deviceSync = await _syncSvc.getDeviceSync(currentDeviceId);

      if (deviceSync != null && deviceSync['call_at'] != null) {
        cutoff = DateTime.parse(deviceSync['call_at']).toLocal();
        lastSyncedCallId = deviceSync['last_sync_call'];
        LoggerService.info(
          '⏳ device_sync found. Cutoff: $cutoff, Last ID: $lastSyncedCallId',
        );
      } else {
        // 🚀 FIRST TIME SYNC: Use 24-hour fallback as requested
        cutoff = dateFrom ?? DateTime.now().subtract(const Duration(hours: 24));
        LoggerService.info(
          '⏳ First-time sync (No record): Fetching calls from last 24 hours ($cutoff)',
        );
      }

      final entries = await CallLog.get();
      final filtered = entries.where((e) {
        final ts = DateTime.fromMillisecondsSinceEpoch(e.timestamp ?? 0);
        final id = '${e.number}_${ts.millisecondsSinceEpoch}';

        // Skip if call is strictly older than cutoff
        if (ts.isBefore(cutoff!)) return false;

        // 🛡️ SMART CHECK: Even if time is same, skip if ID matches exactly
        if (id == lastSyncedCallId) return false;

        return true;
      }).toList();

      if (filtered.isEmpty) {
        LoggerService.info('✅ No new calls found since last sync');
        return 0;
      }

      // Sort by timestamp to process oldest to newest
      filtered.sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));

      int added = 0;
      DateTime? latestCallTime;
      String? latestCallId;

      for (final e in filtered) {
        final ts = DateTime.fromMillisecondsSinceEpoch(e.timestamp ?? 0);
        final id = '${e.number}_${ts.millisecondsSinceEpoch}';

        if (StorageService.syncedBucket.get(id) == null &&
            StorageService.callBucket.get(id) == null) {
          final model = CallLogModel(
            id: id,
            number: e.number ?? '',
            name: e.name,
            callType: _mapType(e.callType),
            duration: e.duration ?? 0,
            timestamp: ts.toUtc(),
            deviceId: currentDeviceId,
          );

          StorageService.callBucket.put(id, {
            'model': model.toJson(),
            'status': 'pending',
          });
          added++;

          if (latestCallTime == null || ts.isAfter(latestCallTime)) {
            latestCallTime = ts;
            latestCallId = id;
          }
        }
      }

      // 2. Update device_sync in Supabase with the latest call metadata
      // This is still needed here because scanAndEnqueueNewCalls handles multiple calls,
      // not just one live call.
      if (latestCallTime != null && latestCallId != null) {
        await _syncSvc.setDeviceSync(
          deviceId: currentDeviceId,
          lastSyncCall: latestCallId,
          callAt: latestCallTime,
        );
      }

      await updateLastSync(DateTime.now().millisecondsSinceEpoch.toString());
      return added;
    } catch (e) {
      LoggerService.error('❌ Scan failed', e);
      return 0;
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

  String _mapType(CallType? t) {
    if (t == CallType.incoming) return 'incoming';
    if (t == CallType.outgoing) return 'outgoing';
    if (t == CallType.missed) return 'missed';
    return 'unknown';
  }

  Future<bool> sendFakeData() async {
    if (kIsWeb) return false;
    try {
      final currentDeviceId = await DeviceUtils.getDeviceId();
      final ts = DateTime.now().subtract(const Duration(minutes: 5));
      final id = 'fake_${ts.millisecondsSinceEpoch}';

      final model = CallLogModel(
        id: id,
        number: '1234567890',
        name: 'John Doe (Fake)',
        callType: 'incoming',
        duration: 45,
        timestamp: ts.toUtc(),
        deviceId: currentDeviceId,
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
      // We use our custom native overlay instead of the     package
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
}
