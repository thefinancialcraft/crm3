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
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5E17EB), Color(0xFF8A2BE2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5E17EB).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sync Status',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),

          // Status Tabs
          Row(
            children: [
              _buildStatusTab(
                'Pending',
                pending.toString(),
                Colors.orange,
                true,
              ),
              const SizedBox(width: 12),
              _buildStatusTab('Synced', synced.toString(), Colors.green, true),
              const SizedBox(width: 12),
              _buildStatusTab(
                'Status',
                isSyncing ? 'Syncing' : 'Idle',
                isSyncing ? const Color(0xFF5E17EB) : Colors.grey,
                true,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Last Sync Info
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF5E17EB),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.access_time,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Last Sync',
                            style: TextStyle(
                              color: Color(0xFF5E17EB),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            lastSync != null
                                ? '${lastSync!.year}-${lastSync!.month.toString().padLeft(2, '0')}-${lastSync!.day.toString().padLeft(2, '0')} ${lastSync!.hour.toString().padLeft(2, '0')}:${lastSync!.minute.toString().padLeft(2, '0')}:${lastSync!.second.toString().padLeft(2, '0')}'
                                : '-',
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTab(
    String label,
    String value,
    Color color,
    bool showIcon,
  ) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (showIcon) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  label == 'Pending' ? Icons.pending : Icons.check_circle,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(height: 8),
            ] else ...[
              // Add placeholder for consistent height when no icon is shown
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSyncing ? Icons.sync : Icons.pause,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
