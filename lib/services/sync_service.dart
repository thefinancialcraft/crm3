import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'storage_service.dart';
import '../utils/retry.dart';
import '../utils/device_utils.dart';
import 'logger_service.dart';
import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';
import '../models/user_model.dart';
import '../utils/phone_utils.dart';
import 'dart:async';

class SyncService {
  final SupabaseClient client;
  final Function(int pending, int synced)? onProgress;
  final Map<String, Set<String>> _existingCallCache = {};
  DateTime? _lastCacheUpdate;

  SyncService(this.client, {this.onProgress}) {
    LoggerService.info('🏗️ SyncService instance created');
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
  }) async {
    LoggerService.info(
      '🔄 updateSyncMeta called (isLogin: $isLogin, onCall: $onCall, hasError: ${lastError != null})',
    );
    try {
      // 1. Get user data immediately
      UserModel? user;
      try {
        final ctx = LoggerService.navKey.currentContext;
        if (ctx != null) {
          user = ctx.read<SyncProvider>().user;
        }
      } catch (_) {}

      if (user == null) {
        final userMap = StorageService.getUser();
        if (userMap != null) user = UserModel.fromJson(userMap);
      }

      // 2. Fetch device info
      final info = await DeviceUtils.getDeviceInfo();
      final androidId = info['androidId'] ?? 'unknown';
      final deviceModel = "${info['brand'] ?? ''} ${info['model'] ?? ''}"
          .trim();

      final empId = user?.employeeId ?? 'unknown';
      final entryId = '${empId}_$androidId';
      final now = DateTime.now().toUtc().toIso8601String();

      final payload = {
        'entry_id': entryId,
        'employee_id': user?.employeeId,
        'email': user?.email,
        'user_name': user?.userName,
        'device_model': deviceModel.isEmpty ? null : deviceModel,
        'android_id': androidId,
        'device_id': androidId,
        'last_synced_at': now,
        'last_error': lastError,
        'is_login': isLogin, // Pass as-is
        'on_call': onCall ?? false,
      };

      // Only add these to payload if they are not null,
      // or if we are turning off the call.
      if (onCall == true) {
        if (dialedNo != null) payload['dialed_no'] = dialedNo;
        if (isPersonal != null) payload['is_personal'] = isPersonal;
        if (lastCallType != null) payload['call_type'] = lastCallType;
        if (customerName != null) payload['customer_name'] = customerName;
      } else if (onCall == false) {
        // Reset fields when call ends
        payload['dialed_no'] = null;
        payload['is_personal'] = true;
        payload['call_type'] = null;
        payload['customer_name'] = null;
      }

      if (isLogin == true) {
        payload['last_login'] = now;
      }

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

  Future<Map<String, dynamic>?> lookupCustomer(String? phoneNo) async {
    if (phoneNo == null || phoneNo.isEmpty) {
      LoggerService.warn('🔍 Sync: No number provided for customer lookup');
      return null;
    }
    final normalized = PhoneUtils.normalize(phoneNo);
    LoggerService.info('🔍 Sync: Normalizing $phoneNo -> $normalized');

    if (normalized.isEmpty) return null;

    try {
      final resp = await client
          .from('customers')
          .select('id, phone_no, customer_name')
          .ilike('phone_no', normalized)
          .limit(1)
          .maybeSingle();

      LoggerService.info('🔍 Sync: Raw lookup response: $resp');

      if (resp != null && resp['phone_no'] != null) {
        final dbPhone = PhoneUtils.normalize(resp['phone_no'].toString());
        // Verify match locally to be 100% sure
        final isMatch =
            dbPhone.contains(normalized) || normalized.contains(dbPhone);

        LoggerService.info(
          '🔍 Sync: Match check - DB: $dbPhone vs Local: $normalized = $isMatch',
        );
        return isMatch ? resp : null;
      }

      LoggerService.warn(
        '🔍 Sync: No matching customer found (Response was null or empty)',
      );
      return null;
    } catch (e) {
      LoggerService.warn('🔍 Sync: Customer lookup failed: $e');
      return null;
    }
  }

  Future<void> updateLiveCallStatus({
    required bool isOnCall,
    String? number,
    String? callType,
  }) async {
    LoggerService.info(
      '🔄 Sync: updateLiveCallStatus (active=$isOnCall, type=$callType)',
    );
    String? custName;
    bool? isPersonal;

    if (isOnCall && number != null) {
      LoggerService.ui('🔍 Classifying: $number');
      final cust = await lookupCustomer(number);
      final isCust = cust != null;
      custName = cust?['customer_name'] as String?;
      isPersonal = !isCust;
      LoggerService.ui(
        '👤 Type: ${isPersonal ? "Personal" : "Customer (${custName ?? 'Unknown'})"}',
      );
    }

    await updateSyncMeta(
      onCall: isOnCall,
      dialedNo: isOnCall ? number : null,
      lastCallType: callType,
      isPersonal: isPersonal,
      customerName: custName,
      isLogin: null,
    );
  }

  /// Manually logs a call to call_history (used for live-only tracking)
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

      final data = {
        'number': number,
        'call_type': callType,
        'duration': duration,
        'timestamp': ts.toUtc().toIso8601String(),
        'device_id': deviceId,
        'is_personal': isPersonal,
      };

      LoggerService.info('📜 Sync: Manually logging call: $callType ($number)');

      // Prevent duplicates by checking cache
      if (_isDuplicate(deviceId, data)) {
        LoggerService.info('📜 Sync: Skipping duplicate manual log');
        return;
      }

      await client.from('call_history').insert(data);
      LoggerService.info('📜 Sync: Manual log successful');

      // Update cache
      if (_existingCallCache[deviceId] == null) {
        await _updateExistingCallCache(deviceId);
      }
      final key = [
        number,
        data['timestamp'],
        duration.toString(),
        callType,
      ].join('_');
      _existingCallCache[deviceId]?.add(key);
    } catch (e) {
      LoggerService.error('❌ Sync: Failed to manual log call', e);
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
          final callType = r['call_type']?.toString() ?? '';
          existingSet.add([number, timestamp, duration, callType].join('_'));
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
    try {
      final number = modelMap['number']?.toString() ?? '';
      final ts = DateTime.parse(
        modelMap['timestamp'],
      ).toUtc().toIso8601String();
      final duration = modelMap['duration']?.toString() ?? '';
      final callType = modelMap['call_type']?.toString() ?? '';
      final key = [number, ts, duration, callType].join('_');

      return _existingCallCache[deviceId]?.contains(key) ?? false;
    } catch (e) {
      LoggerService.warn('Error checking duplicate: $e');
      return false;
    }
  }

  Future<void> syncPending() async {
    LoggerService.info('SyncService.syncPending started');
    LoggerService.ui('Sync started');

    try {
      StorageService.setSyncStatus('running');
    } catch (_) {}

    final box = StorageService.callBucket;
    final keys = box.keys.toList();

    LoggerService.info('Pending items in callBucket: ${keys.length}');
    if (keys.isEmpty) {
      LoggerService.info('No pending items to sync - updating metadata only');
      LoggerService.ui('Checking sync status...');

      // Still update meta even if no calls, as a heartbeat
      await updateSyncMeta();

      StorageService.setSyncStatus('idle');
      return;
    }

    // Group calls by device ID
    final Map<String, List<Map<String, dynamic>>> byDevice = {};
    for (final key in keys) {
      try {
        final data = box.get(key);
        if (data is! Map) continue;

        final modelMap = data['model'] as Map?;
        if (modelMap == null) continue;

        final deviceId =
            modelMap['device_id']?.toString() ??
            await DeviceUtils.getDeviceId();
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
  }

  Future<void> _syncDeviceCalls(
    String deviceId,
    List<Map<String, dynamic>> calls,
  ) async {
    // Update the cache of existing calls
    await _updateExistingCallCache(deviceId);

    // Filter out duplicates before attempting sync
    final toUpload = <Map<String, dynamic>>[];

    for (final call in calls) {
      final modelMap = Map<String, dynamic>.from(call['model']);
      if (!_isDuplicate(deviceId, modelMap) || call['status'] == 'failed') {
        // Apply is_personal classification before upload
        final number = modelMap['number']?.toString();
        final cust = await lookupCustomer(number);
        final isCust = cust != null;
        modelMap['is_personal'] = !isCust;

        // Ensure call_type is set (usually already in model)
        // modelMap['call_type'] = modelMap['call_type'] ?? 'unknown';

        // Remove custom id to let Supabase generate UUID
        modelMap.remove('id');
        toUpload.add({'id': call['id'], 'model': modelMap});
      } else {
        // Mark duplicate as synced and remove from pending
        final id = call['id']?.toString();
        if (id != null) {
          StorageService.syncedBucket.put(id, DateTime.now().toIso8601String());
          StorageService.callBucket.delete(id);
          LoggerService.info('Skipped duplicate call: $id');
        }
      }
    }

    if (toUpload.isEmpty) {
      LoggerService.info('No new calls to sync for device $deviceId');
      return;
    }

    // Process in smaller batches to avoid timeouts
    const batchSize = 50;
    for (var i = 0; i < toUpload.length; i += batchSize) {
      final batch = toUpload.skip(i).take(batchSize).toList();
      final batchModels = batch.map((c) => c['model']).toList();

      try {
        await Retry.retry(() async {
          await client.from('call_history').insert(batchModels).select();
        });

        // Mark successful batch as synced
        final now = DateTime.now().toIso8601String();
        for (final call in batch) {
          final id = call['id']?.toString();
          if (id != null) {
            StorageService.syncedBucket.put(id, now);
            StorageService.callBucket.delete(id);
          }
        }

        // Update the cache with newly synced calls
        for (final modelMap in batchModels) {
          try {
            final number = modelMap['number']?.toString() ?? '';
            final ts = DateTime.parse(
              modelMap['timestamp'],
            ).toUtc().toIso8601String();
            final duration = modelMap['duration']?.toString() ?? '';
            final callType = modelMap['call_type']?.toString() ?? '';
            final key = [number, ts, duration, callType].join('_');
            _existingCallCache[deviceId]?.add(key);
          } catch (_) {}
        }

        // Update progress
        if (onProgress != null) {
          final pendingCount = StorageService.callBucket.length;
          final syncedCount = StorageService.syncedBucket.length;
          onProgress!(pendingCount, syncedCount);
        }

        LoggerService.info(
          'Synced batch of ${batch.length} calls for device $deviceId',
        );
      } catch (e) {
        LoggerService.warn('Error syncing batch for device $deviceId: $e');

        // Update sync meta with error
        await updateSyncMeta(lastError: e.toString());

        // Mark batch as failed
        for (final call in batch) {
          try {
            final id = call['id']?.toString();
            if (id != null) {
              final data = StorageService.callBucket.get(id);
              if (data is Map) {
                data['status'] = 'failed';
                data['lastError'] = e.toString();
                data['attempts'] = (data['attempts'] ?? 0) + 1;
                StorageService.callBucket.put(id, data);
              }
            }
          } catch (_) {}
        }
      }
    }
  }
}
