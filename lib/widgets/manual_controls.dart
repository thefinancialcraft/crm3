import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/sync_provider.dart';
import '../services/logger_service.dart';
import '../services/sync_service.dart';
import '../services/storage_service.dart';
import '../services/call_log_service.dart';

class ManualControls extends StatefulWidget {
  const ManualControls({super.key});

  @override
  State<ManualControls> createState() => _ManualControlsState();
}

class _ManualControlsState extends State<ManualControls> {
  bool _isSyncing = false;
  bool _isSendingFakeData = false;
  bool _isClearingBuckets = false;

  @override
  Widget build(BuildContext context) {
    final sync = context.read<SyncProvider>();
    return Column(
      children: [
        _buildControlCard(
          context,
          icon: Icons.sync,
          title: 'Start Sync',
          subtitle: 'Sync pending call logs',
          color: const Color(0xFF5E17EB),
          isLoading: _isSyncing,
          onTap: () async {
            if (_isSyncing) return;

            setState(() {
              _isSyncing = true;
            });

            LoggerService.ui('Start Sync tapped');
            sync.setSyncing(true);
            final callSvc = CallLogService();
            try {
              // First scan device call logs and enqueue any new entries
              await callSvc.scanAndEnqueueNewCalls();

              // Then attempt to sync pending items to Supabase
              // Pass callback to update SyncProvider in real-time as each item syncs
              final svc = SyncService(
                Supabase.instance.client,
                onProgress: (pending, synced) {
                  sync.setCounts(pending: pending, synced: synced);
                  sync.setLastSync(DateTime.now());
                },
              );
              await svc.syncPending();

              // Final update after sync completes
              final pending = StorageService.callBucket.length;
              final synced = StorageService.syncedBucket.length;
              sync.setCounts(pending: pending, synced: synced);
              sync.setLastSync(DateTime.now());
              LoggerService.info('Manual sync complete');
            } catch (e, st) {
              LoggerService.error('Manual sync failed', e, st);
            } finally {
              if (mounted) {
                setState(() {
                  _isSyncing = false;
                });
              }
              sync.setSyncing(false);
            }
          },
        ),
        const SizedBox(height: 12),
        _buildControlCard(
          context,
          icon: Icons.bug_report,
          title: 'Send Fake Data',
          subtitle: 'Generate test call logs',
          color: Colors.green,
          isLoading: _isSendingFakeData,
          onTap: () async {
            if (_isSendingFakeData) return;

            setState(() {
              _isSendingFakeData = true;
            });

            LoggerService.ui('Send Fake Data tapped');
            final callSvc = CallLogService();
            try {
              final ok = await callSvc.sendFakeData();
              if (ok) {
                LoggerService.info('Fake data enqueued locally');
                // Optionally kick off a sync immediately with real-time updates
                final svc = SyncService(
                  Supabase.instance.client,
                  onProgress: (pending, synced) {
                    sync.setCounts(pending: pending, synced: synced);
                    sync.setLastSync(DateTime.now());
                  },
                );
                await svc.syncPending();
                // Final update after sync completes
                final pending = StorageService.callBucket.length;
                final synced = StorageService.syncedBucket.length;
                sync.setCounts(pending: pending, synced: synced);
                sync.setLastSync(DateTime.now());
              } else {
                LoggerService.warn('sendFakeData reported failure');
              }
            } catch (e, st) {
              LoggerService.error('Send fake data failed', e, st);
            } finally {
              if (mounted) {
                setState(() {
                  _isSendingFakeData = false;
                });
              }
            }
          },
        ),
        const SizedBox(height: 12),
        _buildControlCard(
          context,
          icon: Icons.cleaning_services,
          title: 'Clear Buckets',
          subtitle: 'Remove all local data',
          color: Colors.red,
          isLoading: _isClearingBuckets,
          onTap: () {
            if (_isClearingBuckets) return;

            LoggerService.ui('Clear Buckets tapped');
            try {
              final pendingBefore = StorageService.callBucket.length;
              // Show a simple confirmation dialog with count
              showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear local bucket'),
                  content: Text(
                    'This will clear $pendingBefore pending items from local storage.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.of(ctx).pop();

                        // Set loading state for the clear buckets button
                        setState(() {
                          _isClearingBuckets = true;
                        });

                        try {
                          StorageService.clearCallBucket();
                          final pendingAfter = StorageService.callBucket.length;
                          sync.setCounts(
                            pending: pendingAfter,
                            synced: StorageService.syncedBucket.length,
                          );
                          LoggerService.info(
                            'Cleared callBucket: before=$pendingBefore after=$pendingAfter',
                          );
                        } catch (e) {
                          LoggerService.error('Failed to clear buckets: $e');
                        } finally {
                          // Reset loading state for the clear buckets button
                          if (mounted) {
                            setState(() {
                              _isClearingBuckets = false;
                            });
                          }
                        }
                      },
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
            } catch (e) {
              LoggerService.error('Failed to clear buckets flow: $e');
              // Reset loading state in case of exception
              if (mounted) {
                setState(() {
                  _isClearingBuckets = false;
                });
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildControlCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Opacity(
        opacity: isLoading ? 0.7 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              isLoading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(Icons.arrow_forward_ios, color: color, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
