import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/sync_provider.dart';
import '../services/logger_service.dart';
import '../services/sync_service.dart';
import '../services/storage_service.dart';
import '../services/call_log_service.dart';
import '../services/webbridge_service.dart';

class ManualControls extends StatefulWidget {
  const ManualControls({super.key});

  @override
  State<ManualControls> createState() => _ManualControlsState();
}

class _ManualControlsState extends State<ManualControls> {
  bool _isSyncing = false;
  bool _isSendingFakeData = false;
  bool _isClearingBuckets = false;
  final _testNumberController = TextEditingController(text: "9876543210");

  @override
  void dispose() {
    _testNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF5E17EB);
    final sync = context.read<SyncProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('System Operations', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        const SizedBox(height: 12),
        _buildActionTile(
          icon: Icons.sync_rounded,
          title: 'Immediate Sync',
          subtitle: 'Push pending calls to server',
          color: primaryColor,
          isLoading: _isSyncing,
          onTap: () async {
            if (_isSyncing) return;
            setState(() => _isSyncing = true);
            sync.setSyncing(true);
            try {
              await CallLogService().scanAndEnqueueNewCalls();
              final svc = SyncService(Supabase.instance.client, onProgress: (p, s) {
                sync.setCounts(pending: p, synced: s);
                sync.setLastSync(DateTime.now());
              });
              await svc.syncPending();
              sync.setCounts(pending: StorageService.callBucket.length, synced: StorageService.syncedBucket.length);
              sync.setLastSync(DateTime.now());
            } finally {
              if (mounted) setState(() => _isSyncing = false);
              sync.setSyncing(false);
            }
          },
        ),
        const SizedBox(height: 8),
        _buildActionTile(
          icon: Icons.bug_report_rounded,
          title: 'Generate Test Data',
          subtitle: 'Create dummy call entries',
          color: Colors.teal,
          isLoading: _isSendingFakeData,
          onTap: () async {
            if (_isSendingFakeData) return;
            setState(() => _isSendingFakeData = true);
            try {
              final ok = await CallLogService().sendFakeData();
              if (ok) {
                final svc = SyncService(Supabase.instance.client, onProgress: (p, s) {
                  sync.setCounts(pending: p, synced: s);
                  sync.setLastSync(DateTime.now());
                });
                await svc.syncPending();
              }
            } finally {
              if (mounted) setState(() => _isSendingFakeData = false);
            }
          },
        ),
        const SizedBox(height: 8),
        _buildActionTile(
          icon: Icons.delete_sweep_rounded,
          title: 'Purge Local Storage',
          subtitle: 'Clear all local cache buckets',
          color: Colors.redAccent,
          isLoading: _isClearingBuckets,
          onTap: () => _confirmClear(context, sync),
        ),
        const SizedBox(height: 24),
        const Text('Telephony Testing', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _testNumberController,
                  decoration: const InputDecoration(hintText: 'Phone Number', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  keyboardType: TextInputType.phone,
                ),
              ),
              _buildIconButton(Icons.call_rounded, Colors.green, () {
                if (_testNumberController.text.isNotEmpty) CallLogService().placeDirectCall(_testNumberController.text);
              }),
              const SizedBox(width: 8),
              _buildIconButton(Icons.call_end_rounded, Colors.red, () {
                WebBridgeService.notifyCallEnded(_testNumberController.text);
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionTile({required IconData icon, required String title, required String subtitle, required Color color, required bool isLoading, required VoidCallback onTap}) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.withValues(alpha: 0.05)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.01), blurRadius: 5, offset: const Offset(0, 2))]),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withValues(alpha: 0.08), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            if (isLoading) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.grey))) else Icon(Icons.chevron_right_rounded, color: Colors.grey.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 20)),
    );
  }

  void _confirmClear(BuildContext context, SyncProvider sync) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Purge Storage?'),
        content: Text('This will delete ${StorageService.callBucket.length} items permanently from this device.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _isClearingBuckets = true);
              try {
                StorageService.clearCallBucket();
                sync.setCounts(pending: 0, synced: StorageService.syncedBucket.length);
              } finally {
                setState(() => _isClearingBuckets = false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, elevation: 0),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
