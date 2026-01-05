import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:call_log/call_log.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phone_state/phone_state.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
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
  CallLogService._internal() {
    // Constructor required for Singleton, but init happens in initializeCallStateListener
  }

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

  // Sync state flags (persisted in SharedPreferences ideally, or StorageService)
  static const String _firstSyncKey = 'is_first_sync';
  static const String _lastSyncTimeKey = 'last_sync_time';

  // --- INTERNAL STATE (RESET ON EVERY NEW CALL) ---
  CallTrackingState _state = CallTrackingState.idle;
  String? _currentNumber; // Normalized or raw
  DateTime? _callStartTime;
  bool _isPersonal = true; // Default to true until proven otherwise
  String? _customerName;
  bool _isProcessingEnd = false; // Idempotency flag

  // To silence unused variable warning if strict rules apply, use or remove.
  // We use _callStartTime for duration calculation logic if implemented live.
  DateTime? get callStartTime => _callStartTime;
  String? _detectedCallType; // incoming, outgoing

  // --- DEPENDENCIES & SUBSCRIPTIONS ---
  StreamSubscription? _liveCallSubscription;
  Timer? _autoSyncTimer;
  Timer? _postCallDebounceTimer;

  // --- GLOBAL FLAGS ---
  bool _isUserLoggedIn = false;

  // ===========================================================================
  // 1️⃣ INITIALIZATION & LIFECYCLE
  // ===========================================================================

  /// Call this when the app starts or when the background service launches.
  Future<void> initializeCallStateListener() async {
    if (kIsWeb) return;
    LoggerService.info('🚀 CallLogService: Initializing...');

    // 1. Initialize dependencies
    await NotificationService.initialize();

    // 2. Check login status (Sync must NOT run if logged out)
    await _checkLoginStatus();

    // 3. Reset any stale state
    _hardResetSession("Initialization");

    // 4. Start Listening to Live Events
    _startLiveSubscription();

    LoggerService.info('✅ CallLogService: Initialized & Listening');
  }

  Future<void> _checkLoginStatus() async {
    // Check StorageService or Supabase current session
    final session = Supabase.instance.client.auth.currentSession;
    _isUserLoggedIn = session != null;
    LoggerService.info('👤 User Logged In: $_isUserLoggedIn');
  }

  /// Called when User logs in
  Future<void> onUserLogin() async {
    LoggerService.info('👤 Signal: User Logged In');
    _isUserLoggedIn = true;
    _hardResetSession("Login");
    // Auto sync must start immediately after login
    startAutoSync();
  }

  /// Called when User logs out
  Future<void> onUserLogout() async {
    LoggerService.info('👤 Signal: User Logged Out');
    _isUserLoggedIn = false;
    _stopAutoSync();
    _hardResetSession("Logout");
  }

  void _startLiveSubscription() {
    _liveCallSubscription?.cancel();
    try {
      _liveCallSubscription = PhoneState.stream.listen(
        (event) => _handleCallEvent(event),
        onError: (e) => LoggerService.error('❌ Live Call Stream Error', e),
      );
    } catch (e) {
      LoggerService.error('❌ Failed to init PhoneState', e);
    }
  }

  Future<void> disposeCallStateListener() async {
    LoggerService.info('🛑 CallLogService: Disposing...');
    _liveCallSubscription?.cancel();
    _liveCallSubscription = null;
    _stopAutoSync();
    _hardResetSession("Dispose");
  }

  // ===========================================================================
  // 2️⃣ STATE MACHINE (CORE LOGIC)
  // ===========================================================================

  Future<void> _handleCallEvent(PhoneState event) async {
    try {
      final String? rawNumber = event.number;
      final PhoneStateStatus status = event.status;

      LoggerService.info(
        '📞 Event: $status | No: $rawNumber | CurrentState: $_state',
      );

      switch (status) {
        // --- 🟢 CALL START (Ringing) ---
        case PhoneStateStatus.CALL_INCOMING:
          await _handleCallStart(PhoneStateStatus.CALL_INCOMING, rawNumber);
          break;

        // --- � CALL STARTED (Answered / Outgoing) ---
        case PhoneStateStatus.CALL_STARTED:
          if (_state == CallTrackingState.ringing) {
            // Incoming -> Answered
            await _handleCallActive(rawNumber);
          } else if (_state == CallTrackingState.idle) {
            // Idle -> Started (Outgoing)
            await _handleCallStart(PhoneStateStatus.CALL_STARTED, rawNumber);
            // Assume active immediately for outgoing in this model
            await _handleCallActive(rawNumber);
          } else {
            // Already in progress? Update number if needed
            if (_state == CallTrackingState.dialing) {
              await _handleCallActive(rawNumber);
            }
          }
          break;

        // --- 🔴 CALL END (Finished) ---
        case PhoneStateStatus.CALL_ENDED:
          await _handleCallEnd(rawNumber);
          break;

        case PhoneStateStatus.NOTHING:
        default:
          break;
      }
    } catch (e, st) {
      LoggerService.error('❌ Critical State Machine Error', e, st);
      _hardResetSession("Error Recovery");
    }
  }

  // --- TRANSITION HANDLERS ---

  Future<void> _handleCallStart(
    PhoneStateStatus state,
    String? rawNumber,
  ) async {
    _hardResetSession("New Call Start");

    _currentNumber = rawNumber;
    // Map events to type
    _detectedCallType = (state == PhoneStateStatus.CALL_INCOMING)
        ? 'incoming'
        : 'outgoing';

    // Map to internal state
    _state = (state == PhoneStateStatus.CALL_INCOMING)
        ? CallTrackingState.ringing
        : CallTrackingState.dialing;

    _callStartTime = DateTime.now();

    callActiveNotifier.value = true;
    NotificationService.showCallNotification(
      "📞 Call detected: $_detectedCallType",
    );

    await _updateSyncMetaSafely(onCall: true);

    if (_currentNumber != null) {
      // _showOverlay(number: _currentNumber!, status: "Connecting...");
      _classifyNumber(_currentNumber!);
    } else {
      // _showOverlay(status: "Connecting...");
    }
  }

  Future<void> _handleCallActive(String? rawNumber) async {
    // Recovery: If we missed the 'start' event
    if (_state == CallTrackingState.idle) {
      LoggerService.warn(
        '⚠️ Active event received without Start. Auto-recovering.',
      );
      // Assume outgoing if unknown? Or try to guess? Ringing incoming usually takes time.
      // Defaulting to outgoing is safer for "instant connect" scenarios.
      await _handleCallStart(PhoneStateStatus.CALL_STARTED, rawNumber);
    }

    // Recovery: Number might come late
    if (_currentNumber == null && rawNumber != null) {
      _currentNumber = rawNumber;
      if (_currentNumber != null) {
        await _classifyNumber(_currentNumber!);
      }
    }

    _state = CallTrackingState.active;
    callActiveNotifier.value = true;

    NotificationService.showCallActiveNotification(); // "Call is active"

    // 🔄 SYNC META: Ensure 'on_call' is true (refresh)
    await _updateSyncMetaSafely(onCall: true);
  }

  Future<void> _handleCallEnd(String? rawNumber) async {
    // Idempotency check: Don't process the same end event twice
    if (_isProcessingEnd) return;
    _isProcessingEnd = true;

    try {
      LoggerService.info('🏁 Processing Call End...');

      // Recovery: Number might come only at the end
      if (_currentNumber == null && rawNumber != null) {
        _currentNumber = rawNumber;
      }

      // 🕵️ DETECT MISSED CALL
      // Logic: If it was 'incoming' but never reached 'active' state
      if (_detectedCallType == 'incoming' &&
          _state == CallTrackingState.ringing) {
        _detectedCallType = 'missed';
        LoggerService.info('⚠️ Detected Missed Call (Derived)');
      }

      // 💾 PERSISTENCE (Local + Remote)
      if (_currentNumber != null && _isUserLoggedIn) {
        final syncSvc = SyncService(Supabase.instance.client);

        // This function handles:
        // 1. isCustomer check (if not already done)
        // 2. Insert into local storage
        // 3. Attempt push to Supabase
        await syncSvc.logManualCall(
          number: _currentNumber!,
          callType: _detectedCallType ?? 'unknown',
          duration: 0, // Live tracking can't trust duration, 0 is placeholder
          timestamp: DateTime.now(),
        );
      } else {
        if (!_isUserLoggedIn) {
          LoggerService.warn('❌ Failed to log call: User not logged in');
        } else {
          LoggerService.warn('❌ Failed to log call: Number was null');
        }
      }

      // 🔄 SYNC META: on_call = false
      await _updateSyncMetaSafely(onCall: false);

      // Notification Cleanup
      NotificationService.showCallEndedNotification();

      // ⏲️ SCHEDULE AUTO SYNC (Post-Call Enrichment)
      // We schedule this for 1 minute later to allow Android System Logs to populate
      _schedulePostCallEnrichment();
    } finally {
      // ALWAYS cleanup
      callActiveNotifier.value = false;
      _hardResetSession("End Sequence Complete");
    }
  }

  // ===========================================================================
  // 3️⃣ HELPER LOGIC
  // ===========================================================================

  /// Normalizes number and checks 'customers' table to determine is_personal
  Future<void> _classifyNumber(String number) async {
    // Update number notifier immediately
    currentNumberNotifier.value = number;

    if (!_isUserLoggedIn) return;
    try {
      final syncSvc = SyncService(Supabase.instance.client);

      // Check if it's a customer
      final cust = await syncSvc.lookupCustomer(number);
      final bool isCustomer = cust != null;
      _isPersonal = !isCustomer;
      _customerName = cust?['customer_name'] as String?;

      // Update notifiers
      customerNameNotifier.value = _customerName;
      isPersonalNotifier.value = _isPersonal;

      // Update Overlay
      // _showOverlay(
      //   number: number,
      //   name: _customerName,
      //   isPersonal: _isPersonal,
      //   status: "Active",
      // );

      LoggerService.info(
        '🧠 Classification: $number [isCustomer: $isCustomer, isPersonal: $_isPersonal]',
      );

      // Update SyncMeta immediately with classification
      await _updateSyncMetaSafely(
        onCall: true,
      ); // Re-sends with updated dialed_no and is_personal
    } catch (e) {
      LoggerService.warn('⚠️ Classification failed: $e');
    }
  }

  /// Wrapper to update sync_meta without crashing
  Future<void> _updateSyncMetaSafely({required bool onCall}) async {
    if (!_isUserLoggedIn) return;
    try {
      final syncSvc = SyncService(Supabase.instance.client);
      await syncSvc.updateSyncMeta(
        onCall: onCall,
        dialedNo: onCall ? _currentNumber : null,
        lastCallType: onCall ? _detectedCallType : null,
        isPersonal: _isPersonal,
        customerName: _customerName,
        isLogin: true, // If we are here, we are logged in
      );
    } catch (e) {
      LoggerService.error('❌ SyncMeta update failed', e);
    }
  }

  /// Strictly resets all session state variables.
  void _hardResetSession(String reason) {
    LoggerService.info('🧹 Session Hard Reset: $reason');
    currentNumberNotifier.value = null;
    customerNameNotifier.value = null;
    isPersonalNotifier.value = true;

    _state = CallTrackingState.idle;
    _currentNumber = null;
    _detectedCallType = null;
    _isPersonal = true;
    _customerName = null;
    _callStartTime = null;
    _isPersonal = true; // reset default
    _isProcessingEnd = false;

    // Stop any short-term debounce timers
    _postCallDebounceTimer?.cancel();
    // We do NOT stop _autoSyncTimer here, as that is global

    // Close overlay
    _closeOverlay();
  }

  // ===========================================================================
  // 4️⃣ SYNC SCHEDULING (AUTO & MANUAL)
  // ===========================================================================

  void startAutoSync({
    Duration interval = const Duration(minutes: 15),
    Function(int pending, int synced)? onProgress,
  }) {
    if (!_isUserLoggedIn) {
      LoggerService.warn('🚫 Cannot start Auto Sync: User not logged in');
      return;
    }

    LoggerService.info('⏳ Starting Auto Sync Scheduler...');
    _autoSyncTimer?.cancel();

    // Run periodically (e.g., every 15 minutes)
    _autoSyncTimer = Timer.periodic(interval, (timer) {
      if (_state == CallTrackingState.idle) {
        performBackgroundSync(isAuto: true);
      } else {
        LoggerService.info('⏸️ Auto Sync skipped: Call Active');
      }

      // Update progress callback if provided?
      // Legacy support for onProgress...
    });

    // Also run one immediately
    performBackgroundSync(isAuto: true);
  }

  void _stopAutoSync() {
    LoggerService.info('🛑 Stopping Auto Sync');
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  void _schedulePostCallEnrichment() {
    LoggerService.info('⏲️ Scheduling Post-Call Sync (1 min)...');
    _postCallDebounceTimer?.cancel();
    _postCallDebounceTimer = Timer(const Duration(minutes: 1), () {
      if (_state == CallTrackingState.idle && _isUserLoggedIn) {
        performBackgroundSync(isAuto: true, enrichFromSystemLogs: true);
      }
    });
  }

  /// Triggers a manual sync (allowed anytime, unless dangerous)
  static Future<void> performBackgroundSync({
    bool isAuto = false,
    bool enrichFromSystemLogs = false,
  }) async {
    // Since this method is static in the old version to serve background isolate,
    // we need to be careful. The new design prefers instance methods for state access.
    // However, keeping static for compatibility with background_service.dart calling it directly.

    // We can access the singleton to check state
    if (isAuto && !(_instance._isUserLoggedIn)) return;
    if (isAuto && (_instance._state != CallTrackingState.idle)) return;

    LoggerService.info(
      '🔄 Performing Sync (Auto: $isAuto, Enrich: $enrichFromSystemLogs)',
    );

    try {
      final syncSvc = SyncService(Supabase.instance.client);

      // 1. Sync pending manual logs from local storage
      await syncSvc.syncPending();

      // 2. (Optional) Enrich from Android System Logs
      // This is the ONLY place we touch Android Call Logs
      if (enrichFromSystemLogs && !kIsWeb) {
        await _instance.scanAndEnqueueNewCalls();
        await syncSvc.syncPending();
      }
    } catch (e) {
      LoggerService.error('❌ Sync failed', e);
    }
  }

  // ===========================================================================
  // 5️⃣ LEGACY / UTIL METHODS (For Post-Call Enrichment)
  // ===========================================================================

  /// Scans Android System Call Log to find details we might have missed in live tracking
  /// or to correct durations.
  Future<int> scanAndEnqueueNewCalls({DateTime? dateFrom}) async {
    if (kIsWeb) return 0;
    LoggerService.info('🔎 Scanning Android Call Log for enrichment...');

    try {
      final lastSync = dateFrom ?? await getLastSyncTime();
      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
      final cutoff = lastSync ?? threeDaysAgo;
      final currentDeviceId = await DeviceUtils.getDeviceId();

      // Fetch native logs
      final Iterable<CallLogEntry> entries = await CallLog.get();
      final filteredEntries = entries.where((e) {
        final ts = DateTime.fromMillisecondsSinceEpoch(e.timestamp ?? 0);
        return ts.isAfter(cutoff);
      }).toList();

      final supabase = Supabase.instance.client;
      final existingCalls = await supabase
          .from('call_history')
          .select('number,timestamp,duration,call_type')
          .eq('device_id', currentDeviceId)
          .gte('timestamp', cutoff.toIso8601String());

      final existingSet = <String>{};
      for (final call in existingCalls as List) {
        try {
          final key = [
            call['number']?.toString() ?? '',
            call['timestamp']?.toString() ?? '',
            call['duration']?.toString() ?? '',
            call['call_type']?.toString() ?? '',
          ].join('_');
          existingSet.add(key);
        } catch (_) {}
      }

      int added = 0;
      for (final e in filteredEntries) {
        final ts = DateTime.fromMillisecondsSinceEpoch(e.timestamp ?? 0);
        final id = _generateId(e.number ?? '', ts);

        final isLocalDuplicate =
            StorageService.syncedBucket.get(id) != null ||
            StorageService.callBucket.get(id) != null;

        if (!isLocalDuplicate) {
          final number = e.number ?? '';
          final timestamp = ts.toUtc().toIso8601String();
          final duration = (e.duration ?? 0).toString();
          final callType = _mapType(e.callType);
          final key = [number, timestamp, duration, callType].join('_');

          if (!existingSet.contains(key)) {
            // We can update an existing "pending" entry if we find a match on timestamp/number?
            // For now, simple insert logic
            final model = CallLogModel(
              id: id,
              number: number,
              name: e.name,
              callType: callType,
              duration: e.duration ?? 0,
              timestamp: ts.toUtc(),
              deviceId: currentDeviceId,
            );
            StorageService.callBucket.put(id, {
              'model': model.toJson(),
              'status': 'pending',
              'attempts': 0,
              'lastError': null,
            });
            added++;
          }
        }
      }

      await updateLastSync(DateTime.now().millisecondsSinceEpoch.toString());

      return added;
    } catch (e) {
      LoggerService.warn('⚠️ Scan failed: $e');
      return 0;
    }
  }

  static Future<DateTime?> getLastSyncTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_lastSyncTimeKey);
      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> updateLastSync(String val) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _lastSyncTimeKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  /// Generates a fake call log for testing purposes (Manual Control)
  Future<bool> sendFakeData() async {
    try {
      final now = DateTime.now();
      final deviceId = await DeviceUtils.getDeviceId();
      final id = 'test_${now.millisecondsSinceEpoch}';

      final model = CallLogModel(
        id: id,
        number: '+1555000${now.second}', // Random-ish number
        name: 'Test Caller',
        callType: 'incoming',
        duration: 123,
        timestamp: now.toUtc(),
        deviceId: deviceId,
      );

      StorageService.callBucket.put(id, {
        'model': model.toJson(),
        'status': 'pending',
        'attempts': 0,
        'lastError': null,
      });

      LoggerService.info('🧪 Generated fake call log: $id');
      return true;
    } catch (e) {
      LoggerService.error('❌ Failed to generate fake data', e);
      return false;
    }
  }

  // Legacy support for background_service.dart
  static Future<bool> isFirstSyncCompleted() async {
    if (kIsWeb) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_firstSyncKey) ?? false;
  }

  static Future<void> markFirstSyncCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstSyncKey, true);
  }

  String _generateId(String number, DateTime timestamp) {
    final cleanNumber = number.replaceAll(RegExp(r'[^0-9]'), '');
    return '${cleanNumber}_${timestamp.millisecondsSinceEpoch}';
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
      default:
        return t?.name ?? 'unknown';
    }
  }

  // Legacy helper
  static bool get isOnCallRealTime =>
      _instance._state == CallTrackingState.active;

  // --- OVERLAY HELPERS ---
  Future<void> _showOverlay({
    String? number,
    String? name,
    bool? isPersonal,
    String? status,
  }) async {
    if (kIsWeb) return;
    try {
      final bool hasPermission =
          await FlutterOverlayWindow.isPermissionGranted();
      if (!hasPermission) {
        LoggerService.warn('⚠️ Overlay permission NOT granted.');
        NotificationService.showNotification(
          id: 999,
          title: "Permission Missing",
          body: "Tap here to enable 'Display over other apps' for caller ID",
        );
        return;
      }

      // Close existing overlay with delay
      final bool isActive = await FlutterOverlayWindow.isActive();
      if (!isActive) {
        LoggerService.info('📱 Starting overlay...');
        await FlutterOverlayWindow.showOverlay(
          height: 300,
          width: WindowSize.matchParent,
          alignment: OverlayAlignment.topCenter,
          flag: OverlayFlag.defaultFlag,
          visibility: NotificationVisibility.visibilityPublic,
          enableDrag: true, // Native dragging enabled
          overlayTitle: "TFC Nexus",
          overlayContent: "Active Call",
        );
        // Wait for overlay to initialize
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        LoggerService.info('📱 Overlay already active, updating data...');
      }

      LoggerService.info(
        '📤 Sharing data to overlay: $number, $name, $isPersonal',
      );

      await FlutterOverlayWindow.shareData({
        if (number != null) 'number': number,
        if (name != null) 'name': name,
        'isPersonal': isPersonal ?? true,
        if (status != null || _detectedCallType != null)
          'status': status ?? _detectedCallType ?? 'Active Call',
        'callStartTime': _callStartTime?.millisecondsSinceEpoch,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'action': 'update',
      });

      LoggerService.info('✅ Overlay shown successfully');
    } catch (e, stackTrace) {
      LoggerService.error('❌ Overlay Error', e, stackTrace);
    }
  }

  Future<void> _closeOverlay() async {
    if (kIsWeb) return;
    try {
      final bool isActive = await FlutterOverlayWindow.isActive();
      if (isActive) {
        // Share close action first just in case
        await FlutterOverlayWindow.shareData({'action': 'close'});
        await FlutterOverlayWindow.closeOverlay();
      }
    } catch (_) {}
  }

  /// Test method to manually trigger overlay
  Future<void> testOverlay() async {
    LoggerService.info('🧪 Testing Overlay Manual Trigger');
    await _showOverlay(
      number: "+1234567890",
      name: "Test Caller Manual",
      isPersonal: false,
      status: "Testing...",
    );
  }
}
