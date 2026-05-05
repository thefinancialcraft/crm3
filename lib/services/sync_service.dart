import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/retry.dart';
import '../utils/device_utils.dart';
import 'logger_service.dart';
import '../models/user_model.dart';
import '../models/call_log_model.dart';
import '../utils/phone_utils.dart';
import 'dart:async';
import 'call_log_service.dart';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 🌉 THE BRIDGE MODEL: Immutable to prevent side-effect collisions
@immutable
class LiveCallResult {
  final String? number;
  final String? normalized;
  final String? name;
  final bool isPersonal;
  final String? callType;
  final bool isOnCall;

  const LiveCallResult({
    this.number,
    this.normalized,
    this.name,
    this.isPersonal = true,
    this.callType,
    this.isOnCall = false,
  });
}

class SyncService {
  static SyncService? _instance;
  static SyncService get instance {
    if (_instance == null) {
      _instance = SyncService._internal(Supabase.instance.client);
      initWatcher(); // 🚀 START WATCHING BUCKET
    }
    return _instance!;
  }

  // Real-time Notifiers for Dev Mode
  static final ValueNotifier<String> syncProgressNotifier = ValueNotifier<String>('Idle');
  static final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<bool> isSyncingNotifier = ValueNotifier<bool>(false); // 🔄 SYNC STATUS
  static final ValueNotifier<Map<String, dynamic>?> lastSyncedCallNotifier = ValueNotifier<Map<String, dynamic>?>(null);
  
  // 🛰️ REAL-TIME SYNC STREAM: For live UI updates like the logger
  static final _syncEventController = StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get syncEvents => _syncEventController.stream;

  // 🔔 AUTO-WATCHER: Update pending count whenever bucket changes
  static Timer? _watcherDebounceTimer;
  static void initWatcher() {
    pendingCountNotifier.value = StorageService.callBucket.length;
    StorageService.callBucket.listenable().addListener(() {
      final count = StorageService.callBucket.length;
      pendingCountNotifier.value = count;
      
      // 🚀 REACTIVE SYNC: 5 second debounce to prevent rapid-fire syncs
      if (count > 0 && !isSyncingNotifier.value) {
        _watcherDebounceTimer?.cancel();
        _watcherDebounceTimer = Timer(
          const Duration(seconds: 5),
          () => _instance?.scheduleSyncDebounced(delay: Duration.zero)
        );
      }
    });
  }

  final SupabaseClient client;
  Function(int pending, int synced)? onProgress;
  final Map<String, Set<String>> _existingCallCache = {};
  final Set<String> _ongoingSyncKeys = {}; // 🚀 TRACKS LIVE UPLOADS
  DateTime? _lastCacheUpdate;

  // 🚀 OPTIMIZATIONS
  Timer? _syncDebounceTimer;
  bool _isSyncInProgress = false;
  
  final Map<String, Map<String, dynamic>?> _customerCache = {};
  final Map<String, DateTime> _customerCacheTime = {};
  static const _customerCacheDuration = Duration(hours: 1);
  DateTime? _lastLiveUpdate;
  
  void scheduleSyncDebounced({Duration delay = const Duration(seconds: 3)}) {
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(delay, () {
      if (!_isSyncInProgress) {
        syncPending();
      }
    });
  }

  // 🔐 ENCRYPTION CONSTANTS (Replace with actual key)
  static const String phoneEncryptionKey =
      "TfcV2_Secure_9Xk2Lp5Nm8Qj4Rs7Vw1Zy3Bd6G";

  // 🧩 HELPER: Compute SHA-256 Hash for Lookup
  String _computeHash(String phone) {
    // Backend logic: Remove non-digits, then hash
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final bytes = utf8.encode(clean);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // 🌉 ISOLATED BRIDGE: Instance-based stream to prevent global collisions
  final _liveUpdateController = StreamController<LiveCallResult>.broadcast();
  Stream<LiveCallResult> get liveUpdates => _liveUpdateController.stream;

  void dispose() {
    _liveUpdateController.close();
    stopCommandListener();
  }

  RealtimeChannel? _commandChannel;
  Timer? _heartbeatTimer;

  // Track last processed command to avoid infinite loops
  String? _lastValue;
  int? _lastAttempts;

  Future<void> startCommandListener() async {
    final userMap = StorageService.getUser();
    if (userMap == null) return;
    
    final user = UserModel.fromJson(userMap);
    final info = await DeviceUtils.getDeviceInfo();
    final androidId = info['androidId'] ?? 'unknown';
    final entryId = '${user.employeeId}_$androidId';
    // UNIQUE CHANNEL NAME PER DEVICE
    final channelName = 'sync_commands_$androidId';

    LoggerService.info('🚀 Sync: Starting Command Listener for $entryId on $channelName');

    await stopCommandListener();
    startHeartbeat(); // 💓 Start the 30s heartbeat

    // Use a simpler channel name and rely on the filter
    _commandChannel = client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'sync_meta',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'entry_id',
            value: entryId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final type = data['type']?.toString();
            final value = data['value']?.toString();
            final attempts = int.tryParse(data['command_attempts']?.toString() ?? '0') ?? 0;

            LoggerService.info('🔔 Sync: Received Command Update -> type: $type, value: $value, attempts: $attempts');

            if (type == null || type.isEmpty) {
              // Command was cleared, reset loop protection
              _lastValue = null;
              _lastAttempts = null;
              return;
            }

            final callSvc = CallLogService();
            final currentNo = CallLogService.currentlyTrackedNumber;
            final isOnCall = CallLogService.isOnCallRealTime;

            final cleanNew = PhoneUtils.normalize(value ?? '');
            final cleanCurrent = currentNo != null ? PhoneUtils.normalize(currentNo) : '';
            
            // Loop protection: Only skip if it's the EXACT same value and attempts count
            // that we just processed.
            if (cleanNew == _lastValue && attempts == _lastAttempts) {
              LoggerService.info('♻️ Sync: Skipping redundant command update');
              return;
            }
            
            _lastValue = cleanNew;
            _lastAttempts = attempts;

            LoggerService.info('📥 Remote Command: type=$type, value=$value, attempts=$attempts');
            
            if (type == 'call_to') {
              if (value != null && value.isNotEmpty) {
                if (cleanNew == cleanCurrent) {
                  LoggerService.info('🚫 Remote Call: $value already active/dialing, skipping.');
                  // Clear command if it's already "processed" by being current
                  await updateSyncMeta(onCall: true, type: null, value: null, commandAttempts: 0);
                  return;
                }
                  
                  if (attempts >= 3) {
                    LoggerService.warn('⚠️ Remote Call: Max attempts reached for $value. Clearing command.');
                    await updateSyncMeta(onCall: isOnCall, type: null, value: null, commandAttempts: 0);
                    return;
                  }

                  LoggerService.info('📞 Remote Call: Placing call to $value (Attempt ${attempts + 1})');
                  
                  // Increment attempt count in DB
                  // Note: This will re-trigger the listener, so we should be careful.
                  // But since we are about to place the call, the next trigger will likely 
                  // see isOnCall=true or just skip if the number is the same.
                  await updateSyncMeta(
                    onCall: isOnCall,
                    commandAttempts: attempts + 1,
                    // Keep type/value so we know we are still trying
                  );
                  
                await callSvc.placeDirectCall(value);
              }
            } else if (type == 'call_disconnect') {
              if (isOnCall) {
                LoggerService.info('📞 Remote Disconnect: Hanging up active call.');
                await callSvc.disconnectCall();
              } else {
                LoggerService.info('🚫 Remote Disconnect: No active call to hang up.');
                // Clear the command since there's nothing to do
                await updateSyncMeta(onCall: false, type: null, value: null, commandAttempts: 0);
              }
            }
          },
        )
        .subscribe((status, error) {
          if (error != null) {
            LoggerService.error('📡 Sync: Command Listener Error: $error', error);
          } else {
            LoggerService.info('📡 Sync: Command Listener Status: $status');
          }
        });
  }

  Future<void> startHeartbeat() async {
    _heartbeatTimer?.cancel();
    LoggerService.info('💓 Sync: Heartbeat initialized (30s interval)');
    
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!StorageService.isLoggedIn()) {
        stopHeartbeat();
        return;
      }
      
      LoggerService.info('💓 Sync: Heartbeat pulse');
      await updateSyncMeta(); // Updates last_seen in DB
    });
  }

  void stopHeartbeat() {
    if (_heartbeatTimer != null) {
      LoggerService.info('🛑 Sync: Stopping Heartbeat');
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
    }
  }

  Future<void> stopCommandListener() async {
    stopHeartbeat(); // Stop heartbeat when listener stops
    if (_commandChannel != null) {
      LoggerService.info('🛑 Sync: Stopping Command Listener');
      await client.removeChannel(_commandChannel!);
      _commandChannel = null;
    }
  }

  SyncService._internal(this.client, {this.onProgress});

  // Keep supporting the default constructor for backward compatibility if needed,
  // but internally it should probably just point to instance or be deprecated.
  factory SyncService(SupabaseClient client, {Function(int, int)? onProgress}) {
    _instance ??= SyncService._internal(client, onProgress: onProgress);
    return _instance!;
  }

  /// Update the sync_meta table in Supabase
  Future<void> updateSyncMeta({
    String? lastError,
    bool? isLogin,
    bool? onCall,
    String? dialedNo,
    String? lastCallType,
    bool? isPersonal,
    String? customerName,
    String? type,
    String? value,
    String? callingStatus,
    int? commandAttempts,
  }) async {
    LoggerService.info(
      '🔄 updateSyncMeta called (isLogin: $isLogin, onCall: $onCall, hasError: ${lastError != null}, type: $type, value: $value)',
    );
    try {
      // 1. Get user data immediately
      UserModel? user;
      final userMap = StorageService.getUser();
      if (userMap != null) user = UserModel.fromJson(userMap);

      // If user is null and it's not a login attempt, we might be in a logout transition
      // We still need the employeeId to update sync_meta
      if (user == null && isLogin != true) {
        LoggerService.info('📜 Sync: No user found for sync_meta update');
        return;
      }

      // 2. Fetch device info
      final info = await DeviceUtils.getDeviceInfo();
      final androidId = info['androidId'] ?? 'unknown';
      final deviceModel = "${info['brand'] ?? ''} ${info['model'] ?? ''}"
          .trim();

      if (user == null) {
        LoggerService.warn('⚠️ Sync: Cannot update sync_meta because user is null');
        return;
      }

      final empId = user.employeeId;
      final entryId = '${empId}_$androidId';
      final now = DateTime.now().toUtc().toIso8601String();

      final payload = {
        'entry_id': entryId,
        'employee_id': user.employeeId,
        'email': user.email,
        'user_name': user.userName,
        'device_model': deviceModel.isEmpty ? null : deviceModel,
        'android_id': androidId,
        'device_id': androidId,
        'last_synced_at': now,
        'last_error': lastError,
        'on_call': onCall ?? false,
        'organization_id': user.organizationId,
        'command_attempts': commandAttempts ?? 0,
      };

      // Only update is_login and status if it's explicitly provided (true for login, false for logout)
      if (isLogin != null) {
        payload['is_login'] = isLogin;
        payload['status'] = isLogin ? 'connected' : 'disconnected';
        if (isLogin) payload['last_login'] = now;
      }

      // Only add these to payload if they are not null,
      // or if we are turning off the call.
      if (onCall == true) {
        payload['dialed_no'] = dialedNo;
        payload['is_personal'] = isPersonal ?? true;
        payload['call_type'] = lastCallType;
        payload['customer_name'] = customerName;
        if (type != null) payload['type'] = type;
        if (value != null) payload['value'] = value;
        if (callingStatus != null) payload['calling_status'] = callingStatus;
      } else if (onCall == false) {
        // Reset fields when call ends
        payload['dialed_no'] = null;
        payload['is_personal'] = true;
        payload['call_type'] = null;
        payload['customer_name'] = null;
        payload['type'] = null;
        payload['value'] = null;
        payload['calling_status'] = null;
        payload['command_attempts'] = 0;
      }

      // Handled above in isLogin check

      LoggerService.info(
        '📤 Upserting sync_meta for $entryId: ${jsonEncode(payload)}',
      );

      try {
        await client.from('sync_meta').upsert(payload, onConflict: 'entry_id');
        LoggerService.info('✅ sync_meta updated successfully for $entryId');
      } catch (e) {
        LoggerService.error('❌ Failed to upsert sync_meta: $e');
      }
    } catch (e, st) {
      LoggerService.error('❌ updateSyncMeta critical failure', e, st);
    }
  }

  /// Fetches the last sync metadata for this device from Supabase
  Future<Map<String, dynamic>?> getDeviceSync(String deviceId) async {
    try {
      final resp = await client
          .from('device_sync')
          .select()
          .eq('device_id', deviceId)
          .maybeSingle();
      return resp;
    } catch (e) {
      LoggerService.error('❌ Failed to fetch device_sync', e);
      return null;
    }
  }

  /// Updates the last sync metadata for this device
  Future<void> setDeviceSync({
    required String deviceId,
    required String lastSyncCall,
    required DateTime callAt,
  }) async {
    try {
      final payload = {
        'device_id': deviceId,
        'last_sync_at': DateTime.now().toUtc().toIso8601String(),
        'last_sync_call': lastSyncCall,
        'call_at': callAt.toUtc().toIso8601String(),
      };
      await client.from('device_sync').upsert(payload, onConflict: 'device_id');
      LoggerService.info('✅ device_sync updated for $deviceId');
    } catch (e) {
      LoggerService.error('❌ Failed to update device_sync', e);
    }
  }

  Future<Map<String, dynamic>?> lookupCustomer(String? phoneNo) async {
    if (phoneNo == null || phoneNo.isEmpty) return null;
    final normalized = PhoneUtils.normalize(phoneNo);
    if (normalized.isEmpty) return null;

    // 🚀 CACHE CHECK (1 Hour duration)
    final cachedTime = _customerCacheTime[normalized];
    if (cachedTime != null &&
        DateTime.now().difference(cachedTime) < _customerCacheDuration &&
        _customerCache.containsKey(normalized)) {
      LoggerService.info('🔍 Sync: Returning cached lookup for $normalized');
      return _customerCache[normalized];
    }

    // 🚀 LOGIN LOCK: No data fetching without a valid session
    final userMap = StorageService.getUser();
    if (userMap == null || !StorageService.isLoggedIn()) {
      LoggerService.warn('🔍 Sync: Lookup skipped (User not logged in)');
      return null;
    }
    
    // 🛡️ CONDITIONAL FILTERING: Use orgId ONLY if is_client is true
    final bool isClient = userMap['is_client'] == true;
    final String? orgId = isClient ? StorageService.getOrgId() : null;
    
    final hash = _computeHash(normalized);
    LoggerService.info('🔍 Sync: Starting deep lookup for hash: $hash (Org: $orgId)');

    try {
      // 🚀 1. Primary Lookup: Customers Table
      var query = client
          .from('customers')
          .select('id, phone_no, customer_name, organization_id, status, expiry_date, customer_details, utilities, notes, outcome, disposition, sub_disposition')
          .eq('phone_search_hash', hash);
      
      if (orgId != null) {
        query = query.or('organization_id.eq.$orgId,organization_id.is.null');
      }
      
      final List<dynamic> custResp = await query;
      
      if (custResp.isNotEmpty) {
        LoggerService.info('✅ Sync: Found match in CUSTOMERS table');
        final match = custResp.first;
        match['status'] ??= 'Active'; // 🚀 Default for customers
        _customerCache[normalized] = match;
        _customerCacheTime[normalized] = DateTime.now();
        return match;
      }

      // 🚀 2. Secondary Lookup: Rejected Leads
      LoggerService.info('🔍 Sync: No match in customers, checking REJECTED_LEADS...');
      var rejQuery = client
          .from('rejected_leads')
          .select('id, phone_no, customer_name, organization_id, status, expiry_date, customer_details, utilities, notes, outcome, disposition, sub_disposition')
          .eq('phone_search_hash', hash);
      
      if (orgId != null) {
        rejQuery = rejQuery.or('organization_id.eq.$orgId,organization_id.is.null');
      }
      
      final List<dynamic> rejResp = await rejQuery;
      
      if (rejResp.isNotEmpty) {
        LoggerService.info('✅ Sync: Found match in REJECTED_LEADS table');
        final match = rejResp.first;
        match['status'] ??= 'Rejected'; // 🚀 Default for rejected_leads
        _customerCache[normalized] = match;
        _customerCacheTime[normalized] = DateTime.now();
        return match;
      }

      // 🚀 3. Tertiary Lookup: Closed Deals
      LoggerService.info('🔍 Sync: No match in rejected, checking CLOSED_DEALS...');
      var closedQuery = client
          .from('closed_deals')
          .select('id, phone_no, customer_name, organization_id, status, expiry_date, customer_details, utilities, notes, outcome, disposition, sub_disposition')
          .eq('phone_search_hash', hash);
      
      if (orgId != null) {
        closedQuery = closedQuery.or('organization_id.eq.$orgId,organization_id.is.null');
      }
      
      final List<dynamic> closedResp = await closedQuery;
      
      if (closedResp.isNotEmpty) {
        LoggerService.info('✅ Sync: Found match in CLOSED_DEALS table');
        final match = closedResp.first;
        match['status'] ??= 'Closed'; // 🚀 Default for closed_deals
        _customerCache[normalized] = match;
        _customerCacheTime[normalized] = DateTime.now();
        return match;
      }

      LoggerService.info('❌ Sync: No match found in any table for $normalized');
      return null;
    } catch (e) {
      LoggerService.error('🔍 Sync: Customer lookup critical failure for $phoneNo', e);
      return null;
    }
  }

  Future<bool> isNumberPersonal(String number) async {
    final clean = PhoneUtils.normalize(number);
    // 1. Check local personal list
    final personalList = StorageService.getPersonalNumbers();
    if (personalList.contains(clean)) return true;
    
    // 2. Check if it's a CRM customer
    final cust = await lookupCustomer(number);
    return cust == null; // If not in CRM, assume personal
  }

  Future<Map<String, dynamic>?> updateLiveCallStatus({
    required bool isOnCall,
    String? number,
    String? callType,
  }) async {
    // 🚀 LOGIN LOCK: No updates without a valid session
    final userMap = StorageService.getUser();
    if (userMap == null) return null;

    // 🚀 THROTTLE: Prevent rapid-fire updates (min 2s between writes)
    final now = DateTime.now();
    if (_lastLiveUpdate != null && now.difference(_lastLiveUpdate!) < const Duration(seconds: 2)) {
      LoggerService.info('updateLiveCallStatus throttled');
      // Still broadcast to local listeners but skip Supabase write
      if (number != null) {
         // Local broadcast logic would go here if we wanted to avoid write but update UI
         // For now, we just proceed if it's been > 2s.
      }
    }
    _lastLiveUpdate = now;

    LoggerService.info(
      '🔄 Sync: updateLiveCallStatus (active=$isOnCall, type=$callType, no=$number)',
    );

    if (!isOnCall) {
      await updateSyncMeta(onCall: false);
      return null;
    }

    String? custName;
    bool isPersonal = true;
    Map<String, dynamic>? customerResult;
    String? normalizedNo;

    if (number != null) {
      // 1. Normalize number (Remove spaces, dashes, and COUNTRY CODE)
      // Logic: Take last 10 digits for Indian numbers, or normalize via PhoneUtils
      String normalized = number.replaceAll(RegExp(r'[^0-9]'), '');
      if (normalized.length > 10) {
        normalized = normalized.substring(normalized.length - 10);
      }
      normalizedNo = normalized;

      LoggerService.ui('🔍 Classifying (Normalized): $normalized');

      // 2. Database Lookup
      customerResult = await lookupCustomer(normalized);

      if (customerResult != null) {
        isPersonal = false;
        custName = customerResult['customer_name'] as String?;
      }

      LoggerService.ui(
        '👤 Result: ${isPersonal ? "Personal" : "Customer ($custName)"}',
      );

      // 3. Update Sync Meta with all details
      await updateSyncMeta(
        onCall: true,
        dialedNo: normalized,
        lastCallType: callType,
        isPersonal: isPersonal,
        customerName: custName,
        isLogin: null,
      );
    }

    // 🚀 MASTER MOVE: Create structured result
    final result = LiveCallResult(
      number: number,
      normalized: normalizedNo,
      name: custName,
      isPersonal: isPersonal,
      callType: callType,
      isOnCall: true,
    );

    // 🌉 BRIDGE: Broadcast this result to anyone listening
    _liveUpdateController.add(result);

    // 🛡️ JSON SAFE RETURN: Ensure details are safe for MethodChannel
    dynamic detailsJson = customerResult?['customer_details'];
    if (detailsJson is Map || detailsJson is List) {
      detailsJson = jsonEncode(detailsJson);
    }

    final Map<String, dynamic> finalMap = {
      'number': normalizedNo,
      'normalized': normalizedNo,
      'name': custName,
      'isPersonal': isPersonal,
      'status': callType, 
      'expiry_date': customerResult?['expiry_date']?.toString(),
      'customer_details': detailsJson,
      'utilities': customerResult?['utilities'],
      'notes': customerResult?['notes'],
      'outcome': customerResult?['outcome'],
      'disposition': customerResult?['disposition'],
      'sub_disposition': customerResult?['sub_disposition'],
    };

    // 🌉 NATIVE BRIDGE: Write to SharedPreferences so Kotlin CallService can pick it up
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('flutter.last_lookup_result', jsonEncode(finalMap));
      LoggerService.info('✅ Sync: Result pushed to SharedPreferences for Native Bridge');
    } catch (e) {
      LoggerService.error('❌ Sync: Failed to push result to SharedPreferences', e);
    }

    return finalMap;
  }

  /// Logs a call to call_history and updates device_sync bookmark in ONE operation
  Future<void> logManualCall({
    required String number,
    required String callType,
    int duration = 0,
    DateTime? timestamp,
  }) async {
    try {
      final ts = timestamp ?? DateTime.now();
      final deviceId = await DeviceUtils.getDeviceId();
      final cust = await lookupCustomer(number);
      final isCust = cust != null;
      final isPersonal = !isCust;
      final name = cust != null ? cust['customer_name'] : null;

      final userMap = StorageService.getUser();

      final cleanNumber = PhoneUtils.normalize(number);
      // ID Format: phone_timestamp_duration
      final id = '${cleanNumber}_${ts.millisecondsSinceEpoch}_$duration';

      final user = userMap != null ? UserModel.fromJson(userMap) : null;

      // 🚀 QUEUE-FIRST MOVE: Always put in local bucket first, never direct to DB
      final model = CallLogModel(
        id: id,
        number: cleanNumber,
        name: name, 
        callType: callType,
        duration: duration,
        timestamp: ts.toUtc(),
        deviceId: deviceId,
        employeeId: user?.employeeId,
        userName: user?.userName,
        organizationId: user?.organizationId,
        isPersonal: isPersonal,
        idx: id,
      );

      await StorageService.callBucket.put(id, {
        'model': model.toJson(),
        'status': 'pending',
        'attempts': 0,
      });

      LoggerService.info('📥 Sync: Call enqueued in local bucket: $id');
      
      // Update device_sync bookmark (optional here, but good for tracking)
      await setDeviceSync(
        deviceId: deviceId,
        lastSyncCall: id,
        callAt: ts,
      );

      // Trigger background sync (non-blocking)
      scheduleSyncDebounced();
    } catch (e) {
      LoggerService.error('❌ Sync: Failed to log call and bookmark for $number', e);
    }
  }

  Future<void> _updateExistingCallCache(String deviceId) async {
    // Only update cache if it's older than 5 minutes
    if (_lastCacheUpdate != null &&
        DateTime.now().difference(_lastCacheUpdate!) <
            const Duration(minutes: 5)) {
      return;
    }

    try {
      final resp = await client
          .from('call_history')
          .select('number,timestamp,duration,call_type,device_id')
          .eq('device_id', deviceId)
          .gte(
            'timestamp',
            DateTime.now()
                .subtract(const Duration(days: 7))
                .toUtc()
                .toIso8601String(),
          );

      final existingSet = <String>{};
      for (final r in resp as List) {
        try {
          final number = r['number']?.toString() ?? '';
          final timestamp = r['timestamp']?.toString() ?? '';
          final duration = r['duration']?.toString() ?? '';
          existingSet.add([number, timestamp, duration].join('_'));
        } catch (_) {}
      }

      _existingCallCache[deviceId] = existingSet;
      _lastCacheUpdate = DateTime.now();
      LoggerService.info(
        'Updated existing call cache for device $deviceId (${existingSet.length} entries)',
      );
    } catch (e) {
      LoggerService.warn(
        'Failed to update existing call cache for device $deviceId: $e',
      );
    }
  }

  bool _isDuplicate(String deviceId, Map<String, dynamic> modelMap) {
    String checkKey = 'unknown';
    try {
      final number = modelMap['number']?.toString() ?? '';
      final ts = modelMap['timestamp']; 
      final duration = modelMap['duration']?.toString() ?? '';
      checkKey = [number, ts, duration].join('_');
      
      // 1. Check if it's in the Hive Synced Bucket (Most Recent Local Truth)
      final localId = '${PhoneUtils.normalize(number)}_${ts}_$duration';
      if (StorageService.syncedBucket.containsKey(localId)) return true;

      // 2. Check server cache OR if it's currently being uploaded
      return (_existingCallCache[deviceId]?.contains(checkKey) ?? false) ||
             _ongoingSyncKeys.contains(checkKey);
    } catch (e) {
      LoggerService.warn('Error checking duplicate: $checkKey: $e');
      return false;
    }
  }

  Future<void> syncPending() async {
    // 🚀 LOGIN LOCK: No syncing without a valid session
    final userMap = StorageService.getUser();
    if (userMap == null) {
      LoggerService.warn('♻️ Sync: syncPending skipped (User not logged in)');
      return;
    }

    if (_isSyncInProgress) {
      LoggerService.info('Sync already in progress, skipping concurrent run.');
      return;
    }
    _isSyncInProgress = true;
    isSyncingNotifier.value = true; // 🔄 Disable buttons

    LoggerService.info('SyncService.syncPending started');
    LoggerService.ui('Sync started');

    try {
      StorageService.setSyncStatus('running');
      final box = StorageService.callBucket;

      while (box.isNotEmpty) {
        // 🚀 BATCHING OPTIMIZATION: Take up to 20 items at a time for bulk processing
        final allKeys = box.keys.toList();
        final batchKeys = allKeys.take(20).toList();
        
        LoggerService.info('Syncing batch of ${batchKeys.length} items (Total remaining: ${allKeys.length})');
        syncProgressNotifier.value = 'Syncing ${batchKeys.length} items...';

        // Group calls by device ID
        final Map<String, List<Map<String, dynamic>>> byDevice = {};
        for (final key in batchKeys) {
          try {
            final data = box.get(key);
            if (data is! Map) continue;

            final modelMap = data['model'] as Map?;
            if (modelMap == null) continue;

            final deviceId = modelMap['device_id']?.toString() ?? await DeviceUtils.getDeviceId();
            byDevice.putIfAbsent(deviceId, () => []).add({
              'id': key,
              'model': Map<String, dynamic>.from(modelMap),
              'status': data['status'] ?? 'pending',
              'attempts': data['attempts'] ?? 0,
            });
          } catch (e) {
            LoggerService.warn('Error grouping call $key: $e');
          }
        }

        // Process each device's calls
        for (final deviceId in byDevice.keys) {
          await _syncDeviceCalls(deviceId, byDevice[deviceId]!);
        }

        // ⚡ THROTTLING: Give system a breath between batches
        if (box.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      // Final cleanup
      final now = DateTime.now();
      StorageService.setLastSync(now);
      StorageService.setSyncStatus('idle');

      // Update sync meta in Supabase
      await updateSyncMeta();

      LoggerService.info('SyncService.syncPending completed');
      LoggerService.ui('Sync completed');

      // Update counts one final time
      if (onProgress != null) {
        final pendingCount = StorageService.callBucket.length;
        final syncedCount = StorageService.syncedBucket.length;
        onProgress!(pendingCount, syncedCount);
      }
    } catch (e) {
      LoggerService.error('Sync failed', e);
    } finally {
      _isSyncInProgress = false;
      isSyncingNotifier.value = false;
      syncProgressNotifier.value = 'Idle';
    }
  }

  Future<void> _syncDeviceCalls(
      String deviceId, List<Map<String, dynamic>> calls) async {

      await _updateExistingCallCache(deviceId);

      // Step 1 — Saare numbers ke liye batch customer lookup
      final uniqueNumbers = calls
          .map((c) => c['model']['number']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toSet();

      // Parallel lookup — sab ek saath (but limited)
      final customerResults = <String, Map<String, dynamic>?>{};
      final batches = uniqueNumbers.toList();

      // 10-10 ke batches mein parallel lookup
      for (int i = 0; i < batches.length; i += 10) {
          final batch = batches.skip(i).take(10).toList();
          final results = await Future.wait(
              batch.map((phoneNo) => lookupCustomer(phoneNo))
          );
          for (int j = 0; j < batch.length; j++) {
              customerResults[batch[j]] = results[j];
          }
      }

      // Step 2 — Filter duplicates, personal calls
      final toUpload = <Map<String, dynamic>>[];
      for (final call in calls) {
          final modelMap = Map<String, dynamic>.from(call['model']);
          final number = modelMap['number']?.toString() ?? '';
          final cust = customerResults[number];

          if (cust == null) {
              // Personal call — skip, mark synced
              final now = DateTime.now().toIso8601String();
              StorageService.syncedBucket.put(
                  call['id'], now);
              StorageService.callBucket.delete(call['id']);

              // Trigger event for UI update
              final m = Map<String, dynamic>.from(call['model'] as Map);
              final displayIdx = m['idx'] ?? '${m['number']}_${DateTime.parse(m['timestamp']).millisecondsSinceEpoch}_${m['duration']}';
              
              final eventData = {
                  'number': m['number'],
                  'name': 'Personal Call',
                  'call_type': m['call_type'],
                  'duration': m['duration'],
                  'timestamp': m['timestamp']?.toString(),
                  'synced_at': now,
                  'idx': displayIdx,
                  'status': 'Personal (Skipped)',
              };

              lastSyncedCallNotifier.value = eventData;
              _syncEventController.add(eventData);
              continue;
          }

          if (_isDuplicate(deviceId, modelMap)) {
              StorageService.syncedBucket.put(
                  call['id'], DateTime.now().toIso8601String());
              StorageService.callBucket.delete(call['id']);
              continue;
          }

          // Customer data attach karo
          modelMap['is_personal'] = false;
          modelMap['name'] = cust['customer_name'];
          modelMap['organization_id'] = cust['organization_id'];
          modelMap.remove('id');
          toUpload.add({'id': call['id'], 'model': modelMap});
      }

      if (toUpload.isEmpty) return;

      // Step 3 — SINGLE bulk upsert (50 calls = 1 DB request)
      try {
          syncProgressNotifier.value = 'Syncing ${toUpload.length} calls...';

          final bulkData = toUpload.map((item) => item['model'] as Map<String, dynamic>).toList();

          await Retry.retry(() async {
              await client.from('call_history').upsert(bulkData, onConflict: 'idx');
          });

          // Success — sab mark karo
          final now = DateTime.now().toIso8601String();
          for (final item in toUpload) {
              final m = item['model'] as Map<String, dynamic>;
              StorageService.syncedBucket.put(item['id'], {
                  'syncedAt': now,
                  'isPersonal': false,
              });
              StorageService.callBucket.delete(item['id']);

              // Ensure IDX exists for display
              final displayIdx = m['idx'] ?? '${m['number']}_${DateTime.parse(m['timestamp']).millisecondsSinceEpoch}_${m['duration']}';

              final eventData = {
                  ...m,
                  'synced_at': now,
                  'idx': displayIdx,
                  'status': 'Synced',
              };

              lastSyncedCallNotifier.value = eventData;
              _syncEventController.add(eventData);
          }

          LoggerService.info('✅ Bulk synced ${toUpload.length} calls in 1 request');
      } catch (e) {
          LoggerService.error('Bulk sync failed: $e');

          // Failure pe individual retry
          for (final item in toUpload) {
              final currentData = StorageService.callBucket.get(item['id']);
              if (currentData is Map) {
                  final attempts = (currentData['attempts'] ?? 0) + 1;
                  if (attempts >= 3) {
                      StorageService.failedBucket.put(item['id'], currentData);
                      StorageService.callBucket.delete(item['id']);
                  } else {
                      StorageService.callBucket.put(item['id'], {
                          ...currentData,
                          'attempts': attempts,
                          'status': 'failed',
                      });
                  }
              }
          }
      }
  }
}
