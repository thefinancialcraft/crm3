import 'package:supabase_flutter/supabase_flutter.dart';
import 'storage_service.dart';
import '../utils/retry.dart';
import '../utils/device_utils.dart';
import 'logger_service.dart';

class SyncService {
  final SupabaseClient client;
  final Function(int pending, int synced)? onProgress;

  SyncService(this.client, {this.onProgress});

  /// Sync a specific call by its ID
  Future<void> syncSpecificCall(String callId) async {
    LoggerService.info('SyncService.syncSpecificCall started for $callId');
    try {
      final callData = StorageService.callBucket.get(callId);
      if (callData == null) {
        throw Exception('Call data not found in bucket');
      }

      if (callData is! Map) {
        throw Exception('Invalid call data format');
      }

      // Check if already synced
      if (StorageService.syncedBucket.containsKey(callId)) {
        LoggerService.info('Call $callId is already synced, skipping');
        return;
      }

      // Get the model data
      final modelMap = Map<String, dynamic>.from(callData['model'] as Map? ?? {});
      modelMap.remove('id'); // Remove custom id, let Supabase auto-generate UUID

      // Mark as uploading
      callData['status'] = 'uploading';
      callData['attempts'] = (callData['attempts'] ?? 0) + 1;
      StorageService.callBucket.put(callId, callData);

      // Try to insert
      await Retry.retry(() async {
        await client.from('call_logs').insert([modelMap]).select();
      });

      // Success - mark as synced
      final now = DateTime.now().toIso8601String();
      StorageService.syncedBucket.put(callId, now);
      StorageService.callBucket.delete(callId);
      LoggerService.info('Successfully synced call $callId');

      // Update sync meta
      try {
        final deviceId = await DeviceUtils.getDeviceId();
        await client.from('sync_meta').upsert({
          'device_id': deviceId,
          'last_synced_at': DateTime.now().toUtc().toIso8601String(),
          'last_error': null,
        });
      } catch (e) {
        LoggerService.warn('Failed to update sync meta: $e');
      }

    } catch (e) {
      LoggerService.error('Failed to sync call $callId: $e');
      
      // Check if it's a duplicate error
      if (e.toString().contains('duplicate key value violates unique constraint')) {
        // Just remove the duplicate entry
        StorageService.callBucket.delete(callId);
        LoggerService.info('Skipping duplicate call: $callId');
      } else {
        // Update failure count in call bucket
        final callData = StorageService.callBucket.get(callId);
        if (callData is Map) {
          callData['status'] = 'failed';
          callData['lastError'] = e.toString();
          StorageService.callBucket.put(callId, callData);
        }
      }
      
      rethrow; // Re-throw to let caller handle retry logic
    }
  }

  Future<void> syncPending() async {
    LoggerService.info('SyncService.syncPending started');
    // Record a UI-level event so the LogsConsole can show user-visible flow
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
      LoggerService.info('SyncService.syncPending completed');
      return;
    }

    // Load all pending wrapper records
    final List<Map<String, dynamic>> pendingRecords = [];
    for (final id in keys) {
      try {
        final data = box.get(id);
        if (data is Map &&
            data.containsKey('model') &&
            data.containsKey('status')) {
          pendingRecords.add({'id': id, ...Map<String, dynamic>.from(data)});
        } else if (data is Map) {
          // legacy plain model map - migrate on the fly
          pendingRecords.add({
            'id': id,
            'model': Map<String, dynamic>.from(data),
            'status': 'pending',
            'attempts': 0,
            'lastError': null,
          });
        }
      } catch (e) {
        LoggerService.warn('Failed to parse pending item $id: $e');
      }
    }

    // Group by deviceId to query existing remote rows per device
    final Map<String, List<Map<String, dynamic>>> byDevice = {};
    for (final rec in pendingRecords) {
      try {
        final modelMap = Map<String, dynamic>.from(rec['model']);
        final deviceId = modelMap['device_id']?.toString() ?? '';
        byDevice.putIfAbsent(deviceId, () => []).add({
          'id': rec['id'],
          'model': modelMap,
          'status': rec['status'],
          'attempts': rec['attempts'],
          'lastError': rec['lastError'],
        });
      } catch (e) {
        // ignore malformed
      }
    }

    for (final entry in byDevice.entries) {
      final deviceId = entry.key;
      final models = entry.value;
      LoggerService.info(
        'Preparing sync for device $deviceId (${models.length} items)',
      );

      // Fetch existing rows for this device from Supabase to avoid duplicates
      List existing = [];
      try {
        final resp = await client
            .from('call_logs')
            .select('number,timestamp,duration,call_type')
            .eq('device_id', deviceId);
        existing = List.from(resp as List);
      } catch (e) {
        LoggerService.warn(
          'Failed to fetch existing logs for device $deviceId: $e',
        );
      }

      final Set<String> existingSet = {};
      for (final r in existing) {
        try {
          final number = r['number']?.toString() ?? '';
          final timestamp = r['timestamp']?.toString() ?? '';
          final duration = r['duration']?.toString() ?? '';
          final callType = r['call_type']?.toString() ?? '';
          existingSet.add([number, timestamp, duration, callType].join('_'));
        } catch (_) {}
      }

      // Filter records that are not present remotely and build CallLogModel list to upload
      final toUpload = <Map<String, dynamic>>[]; // list of {id, model}
      for (final rec in models) {
        try {
          final modelMap = Map<String, dynamic>.from(rec['model']);
          final id = rec['id']?.toString() ?? '';
          final number = modelMap['number']?.toString() ?? '';
          final ts = DateTime.parse(
            modelMap['timestamp'],
          ).toUtc().toIso8601String();
          final duration = modelMap['duration']?.toString() ?? '';
          final callType = modelMap['call_type']?.toString() ?? '';
          final key = [number, ts, duration, callType].join('_');
          if (!existingSet.contains(key)) {
            toUpload.add({
              'id': id,
              'model': modelMap,
              'attempts': rec['attempts'] ?? 0,
            });
          } else {
            // Already exists remotely; mark as synced locally
            try {
              StorageService.syncedBucket.put(
                id,
                DateTime.now().toIso8601String(),
              );
              StorageService.callBucket.delete(id);
              LoggerService.info('Skipping already-synced item $id');
            } catch (_) {}
          }
        } catch (e) {
          // skip malformed
        }
      }

      // Update counts after filtering duplicates (if items were skipped)
      if (onProgress != null && toUpload.length != models.length) {
        // Some items were skipped as duplicates, update counts now
        final pendingCount = StorageService.callBucket.length;
        final syncedCount = StorageService.syncedBucket.length;
        onProgress!(pendingCount, syncedCount);
      }

      if (toUpload.isEmpty) {
        LoggerService.info('No new items to upload for device $deviceId');
        // Still update counts even if nothing to upload
        if (onProgress != null) {
          final pendingCount = StorageService.callBucket.length;
          final syncedCount = StorageService.syncedBucket.length;
          onProgress!(pendingCount, syncedCount);
        }
        continue;
      }

      // Batch upload all items at once for extreme speed
      LoggerService.info(
        'Batch uploading ${toUpload.length} items to Supabase for device $deviceId',
      );

      // Mark all items as uploading
      for (final entry in toUpload) {
        try {
          final id = entry['id'] as String;
          final raw = StorageService.callBucket.get(id);
          if (raw is Map) {
            raw['status'] = 'uploading';
            raw['attempts'] = (raw['attempts'] ?? 0) + 1;
            StorageService.callBucket.put(id, raw);
          }
        } catch (_) {}
      }

      // Update counts immediately after marking as uploading
      if (onProgress != null) {
        final pendingCount = StorageService.callBucket.length;
        final syncedCount = StorageService.syncedBucket.length;
        onProgress!(pendingCount, syncedCount);
      }

      // Prepare batch insert data (remove custom id field)
      final batchData = toUpload.map((entry) {
        final modelMap = Map<String, dynamic>.from(entry['model'] as Map);
        modelMap.remove(
          'id',
        ); // Remove custom id, let Supabase auto-generate UUID
        return modelMap;
      }).toList();

      try {
        // Batch insert all items at once - extremely fast!
        await Retry.retry(() async {
          await client.from('call_logs').insert(batchData).select();
        });

        // Success - mark all items as synced
        final now = DateTime.now().toIso8601String();
        for (final entry in toUpload) {
          try {
            final entryId = entry['id'] as String;
            StorageService.syncedBucket.put(entryId, now);
            StorageService.callBucket.delete(entryId);
          } catch (e) {
            final entryId = entry['id']?.toString() ?? 'unknown';
            LoggerService.warn('Failed to mark $entryId as synced: $e');
          }
        }

        LoggerService.info(
          'Successfully batch synced ${toUpload.length} items for device $deviceId',
        );

        // Update counts immediately after successful batch sync (real-time)
        if (onProgress != null) {
          final pendingCount = StorageService.callBucket.length;
          final syncedCount = StorageService.syncedBucket.length;
          onProgress!(pendingCount, syncedCount);
          // Also update last sync timestamp immediately
          StorageService.setLastSync(DateTime.now());
        }
      } catch (e, st) {
        // Batch upload failed - update sync_meta with error
        try {
          final deviceIdForMeta = await DeviceUtils.getDeviceId();
          await client.from('sync_meta').upsert({
            'device_id': deviceIdForMeta,
            'last_error': e.toString(),
          });
          LoggerService.warn(
            'Updated sync_meta with error for device $deviceIdForMeta',
          );
        } catch (metaError) {
          LoggerService.warn(
            'Failed to update sync_meta with error: $metaError',
          );
        }

        // Check if this is a duplicate key error
        if (e.toString().contains('duplicate key value violates unique constraint')) {
          LoggerService.info(
            'Batch contains duplicates, processing individually to skip duplicates',
          );
          
          // Process each item individually to identify and skip duplicates
          int successfulSyncs = 0;
          int duplicateCount = 0;
          
          for (final entry in toUpload) {
            try {
              final modelMap = Map<String, dynamic>.from(entry['model'] as Map);
              modelMap.remove('id');
              
              await Retry.retry(() async {
                await client.from('call_logs').insert([modelMap]).select();
              });
              
              // Success - mark as synced
              final now = DateTime.now().toIso8601String();
              final entryId = entry['id'] as String;
              StorageService.syncedBucket.put(entryId, now);
              StorageService.callBucket.delete(entryId);
              successfulSyncs++;
              
            } catch (individualError) {
              // Check if this is a duplicate error
              if (individualError.toString().contains('duplicate key value violates unique constraint')) {
                // Just remove the duplicate entry
                final entryId = entry['id'] as String;
                StorageService.callBucket.delete(entryId);
                LoggerService.info('Skipping duplicate entry: $entryId');
              } else {
                // This is a different error, mark as failed
                try {
                  final id = entry['id'] as String;
                  final raw = StorageService.callBucket.get(id);
                  if (raw is Map) {
                    raw['status'] = 'failed';
                    raw['lastError'] = individualError.toString();
                    StorageService.callBucket.put(id, raw);
                  }
                } catch (_) {}
                LoggerService.warn('Failed to sync entry ${entry['id']}: $individualError');
              }
            }
          }
          
          LoggerService.info(
            'Processed batch individually: $successfulSyncs successful, $duplicateCount duplicates skipped',
          );
          
          // Update counts after individual processing
          if (onProgress != null) {
            final pendingCount = StorageService.callBucket.length;
            final syncedCount = StorageService.syncedBucket.length;
            onProgress!(pendingCount, syncedCount);
            StorageService.setLastSync(DateTime.now());
          }
        } else {
          // Not a duplicate error, use fallback approach
          LoggerService.error(
            'Batch upload failed for device $deviceId, trying smaller batches',
            e,
            st,
          );

          // Fallback: Try uploading in smaller batches (100 at a time)
          const batchSize = 100;
          for (int i = 0; i < toUpload.length; i += batchSize) {
            final batch = toUpload.skip(i).take(batchSize).toList();
            final batchData = batch.map((entry) {
              final modelMap = Map<String, dynamic>.from(entry['model'] as Map);
              modelMap.remove('id');
              return modelMap;
            }).toList();

            try {
              await Retry.retry(() async {
                await client.from('call_logs').insert(batchData).select();
              });

              // Mark this batch as synced
              final now = DateTime.now().toIso8601String();
              for (final entry in batch) {
                try {
                  final id = entry['id'] as String;
                  StorageService.syncedBucket.put(id, now);
                  StorageService.callBucket.delete(id);
                } catch (_) {}
              }

              LoggerService.info('Synced batch of ${batch.length} items');

              // Update counts immediately after each batch (real-time)
              if (onProgress != null) {
                final pendingCount = StorageService.callBucket.length;
                final syncedCount = StorageService.syncedBucket.length;
                onProgress!(pendingCount, syncedCount);
                // Also update last sync timestamp in real-time
                StorageService.setLastSync(DateTime.now());
              }
            } catch (batchError) {
              // Check if this is a duplicate key error
              if (batchError.toString().contains('duplicate key value violates unique constraint')) {
                LoggerService.info(
                  'Small batch contains duplicates, processing individually',
                );
                
                // Process each item in the failed batch individually
                for (final entry in batch) {
                  try {
                    final modelMap = Map<String, dynamic>.from(entry['model'] as Map);
                    modelMap.remove('id');
                    
                    await Retry.retry(() async {
                      await client.from('call_logs').insert([modelMap]).select();
                    });
                    
                    // Success - mark as synced
                    final now = DateTime.now().toIso8601String();
                    final entryId = entry['id'] as String;
                    StorageService.syncedBucket.put(entryId, now);
                    StorageService.callBucket.delete(entryId);
                    
                  } catch (individualError) {
                    // Check if this is a duplicate error
                    if (individualError.toString().contains('duplicate key value violates unique constraint')) {
                      // Just remove the duplicate entry
                      final entryId = entry['id'] as String;
                      StorageService.callBucket.delete(entryId);
                      LoggerService.info('Skipping duplicate entry in batch: $entryId');
                    } else {
                      // This is a different error, mark as failed
                      try {
                        final id = entry['id'] as String;
                        final raw = StorageService.callBucket.get(id);
                        if (raw is Map) {
                          raw['status'] = 'failed';
                          raw['lastError'] = individualError.toString();
                          StorageService.callBucket.put(id, raw);
                        }
                      } catch (_) {}
                      LoggerService.warn('Failed to sync entry ${entry['id']} in batch: $individualError');
                    }
                  }
                }
                
                // Update counts after individual processing
                if (onProgress != null) {
                  final pendingCount = StorageService.callBucket.length;
                  final syncedCount = StorageService.syncedBucket.length;
                  onProgress!(pendingCount, syncedCount);
                  StorageService.setLastSync(DateTime.now());
                }
              } else {
                // If even small batch fails with non-duplicate error, mark as failed
                LoggerService.warn('Small batch upload failed: $batchError');
                for (final entry in batch) {
                  try {
                    final id = entry['id'] as String;
                    final raw = StorageService.callBucket.get(id);
                    if (raw is Map) {
                      raw['status'] = 'failed';
                      raw['lastError'] = batchError.toString();
                      StorageService.callBucket.put(id, raw);
                    }
                  } catch (_) {}
                }
              }
            }
          }
        }
      }
    }
    LoggerService.info('SyncService.syncPending completed');
    // UI notification / visible state finished
    LoggerService.ui('Sync completed');
    try {
      final now = DateTime.now();
      StorageService.setLastSync(now);
      StorageService.setSyncStatus('idle');

      // Update sync_meta table in Supabase with last sync time
      try {
        final deviceId = await DeviceUtils.getDeviceId();
        await client.from('sync_meta').upsert({
          'device_id': deviceId,
          'last_synced_at': now.toUtc().toIso8601String(),
          'last_error': null, // Clear any previous error on success
        });
        LoggerService.info('Updated sync_meta table for device $deviceId');
      } catch (e) {
        LoggerService.warn('Failed to update sync_meta table: $e');
      }

      // Final update of counts after sync completes
      if (onProgress != null) {
        final pendingCount = StorageService.callBucket.length;
        final syncedCount = StorageService.syncedBucket.length;
        onProgress!(pendingCount, syncedCount);
      }
    } catch (_) {}
  }
}
