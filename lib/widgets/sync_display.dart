import 'package:flutter/material.dart';

class SyncDisplay extends StatelessWidget {
  final bool isSyncing;
  final int pending;
  final int synced;
  final DateTime? lastSync;

  const SyncDisplay({
    super.key,
    required this.isSyncing,
    required this.pending,
    required this.synced,
    required this.lastSync,
  });

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF5E17EB);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Synchronization', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: (isSyncing ? primaryColor : Colors.grey).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(isSyncing ? 'ACTIVE' : 'IDLE', style: TextStyle(color: isSyncing ? primaryColor : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildLargeStat('Pending', pending.toString(), Colors.orange, Icons.timer_outlined),
              const SizedBox(width: 12),
              _buildLargeStat('Synced', synced.toString(), Colors.green, Icons.cloud_done_outlined),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, size: 16, color: Colors.grey),
                const SizedBox(width: 10),
                const Text('Last Synced', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                const Spacer(),
                Text(lastSync != null ? _formatTime(lastSync!) : 'Never', style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeStat(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.1))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    return '${t.hour}:${t.minute.toString().padLeft(2, '0')} • ${t.day}/${t.month}';
  }
}
