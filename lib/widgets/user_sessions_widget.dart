import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';

class UserSessionsWidget extends StatelessWidget {
  const UserSessionsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final pastUsers = context.watch<SyncProvider>().pastSessions;
    const primaryColor = Color(0xFF5E17EB);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Login History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
            Text('${pastUsers.length} sessions', style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 12),
        if (pastUsers.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
            child: const Center(child: Text('No past sessions recorded.', style: TextStyle(color: Colors.grey, fontSize: 13))),
          )
        else
          SizedBox(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: pastUsers.length,
              itemBuilder: (context, index) {
                final user = pastUsers[index];
                return Container(
                  width: 240,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: primaryColor.withValues(alpha: 0.1)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.01), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.history_rounded, color: primaryColor, size: 14),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(user['name']?.toString() ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildSessionTime('IN', user['firstLogin']),
                      const SizedBox(height: 6),
                      _buildSessionTime('OUT', user['lastLogout'], isLogout: true),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSessionTime(String label, dynamic date, {bool isLogout = false}) {
    final time = _formatDateTimeShort(date);
    return Row(
      children: [
        Container(width: 30, padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: (isLogout ? Colors.orange : Colors.green).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: Center(child: Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: isLogout ? Colors.orange : Colors.green)))),
        const SizedBox(width: 8),
        Text(time, style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
      ],
    );
  }

  String _formatDateTimeShort(dynamic date) {
    if (date == null) return 'N/A';
    try {
      final parsed = date is DateTime ? date : DateTime.tryParse(date.toString());
      if (parsed == null) return date.toString();
      return '${parsed.day}/${parsed.month} ${parsed.hour}:${parsed.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '-';
    }
  }
}
