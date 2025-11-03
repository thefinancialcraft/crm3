import 'package:supabase_flutter/supabase_flutter.dart';
import 'storage_service.dart';
import '../utils/retry.dart';
import '../utils/device_utils.dart';
import 'logger_service.dart';

class SyncService {
  final SupabaseClient client;
  final Function(int pending, int synced)? onProgress;
  final Map<String, Set<String>> _existingCallCache = {};
  DateTime? _lastCacheUpdate;

  SyncService(this.client, {this.onProgress});

  Future<void> _updateExistingCallCache(String deviceId) async {
    // Only update cache if it's older than 5 minutes
    if (_lastCacheUpdate != null &&
        DateTime.now().difference(_lastCacheUpdate!) < const Duration(minutes: 5)) {
      return;
    }

    try {
      final resp = await client
          .from('call_logs')
          .select('number,timestamp,duration,call_type,device_id')
          .eq('device_id', deviceId)
          .gte('timestamp', DateTime.now().subtract(const Duration(days: 7)).toUtc().toIso8601String());

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
      LoggerService.info('Updated existing call cache for device $deviceId (${existingSet.length} entries)');
    } catch (e) {
      LoggerService.warn('Failed to update existing call cache for device $deviceId: $e');
    }
  }

  bool _isDuplicate(String deviceId, Map<String, dynamic> modelMap) {
    try {
      final number = modelMap['number']?.toString() ?? '';
      final ts = DateTime.parse(modelMap['timestamp']).toUtc().toIso8601String();
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
      LoggerService.info('No pending items to sync');
      LoggerService.ui('No pending items to sync');
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

    // Final cleanup
    final now = DateTime.now();
    StorageService.setLastSync(now);
    StorageService.setSyncStatus('idle');
    LoggerService.info('SyncService.syncPending completed');
    LoggerService.ui('Sync completed');

    // Update counts one final time
    if (onProgress != null) {
      final pendingCount = StorageService.callBucket.length;
      final syncedCount = StorageService.syncedBucket.length;
      onProgress!(pendingCount, syncedCount);
    }
  }

  Future<void> _syncDeviceCalls(String deviceId, List<Map<String, dynamic>> calls) async {
    // Update the cache of existing calls
    await _updateExistingCallCache(deviceId);

    // Filter out duplicates before attempting sync
    final toSync = <Map<String, dynamic>>[];
    
    for (final call in calls) {
      final modelMap = Map<String, dynamic>.from(call['model']);
      if (!_isDuplicate(deviceId, modelMap)) {
        // Remove custom id to let Supabase generate UUID
        modelMap.remove('id');
        toSync.add({
          'id': call['id'],
          'model': modelMap,
        });
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

    if (toSync.isEmpty) {
      LoggerService.info('No new calls to sync for device $deviceId');
      return;
    }

    // Process in smaller batches to avoid timeouts
    const batchSize = 50;
    for (var i = 0; i < toSync.length; i += batchSize) {
      final batch = toSync.skip(i).take(batchSize).toList();
      final batchModels = batch.map((c) => c['model']).toList();

      try {
        await Retry.retry(() async {
          await client.from('call_logs').insert(batchModels).select();
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
            final ts = DateTime.parse(modelMap['timestamp']).toUtc().toIso8601String();
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

        LoggerService.info('Synced batch of ${batch.length} calls for device $deviceId');
      } catch (e) {
        LoggerService.warn('Error syncing batch for device $deviceId: $e');
        
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