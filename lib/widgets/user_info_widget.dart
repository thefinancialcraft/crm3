import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';
import '../services/logger_service.dart';

class UserInfoWidget extends StatelessWidget {
  const UserInfoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SyncProvider>().user;
    LoggerService.info(
      "🎨 UserInfoWidget: building for ${user?.userName ?? 'null'}",
    );

    if (user == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Column(
            children: const [
              Icon(Icons.person_off, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                "No User Info Synced",
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Parse dates safely
    DateTime? firstLogin;
    DateTime? lastLogin;
    try {
      if (user.createdAt != null) {
        firstLogin = DateTime.parse(user.createdAt!);
      }
      if (user.lastSignInAt != null) {
        lastLogin = DateTime.parse(user.lastSignInAt!);
      }
    } catch (_) {}

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
            'User Information',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),

          // Profile Header with Icon
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2), // border
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white24,
                  backgroundImage:
                      (user.profilePicUrl != null &&
                          user.profilePicUrl!.isNotEmpty)
                      ? NetworkImage(user.profilePicUrl!)
                      : null,
                  child:
                      (user.profilePicUrl == null ||
                          user.profilePicUrl!.isEmpty)
                      ? const Icon(
                          Icons.account_circle,
                          color: Colors.grey,
                          size: 40,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.userName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${user.employeeId}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    if (user.email.isNotEmpty)
                      Text(
                        user.email,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // User Details Grid
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
                _buildDetailCard(
                  icon: Icons.work,
                  title: 'Role',
                  value: user.role,
                  color: Colors.green,
                ),
                if (user.designation.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildDetailCard(
                    icon: Icons.badge,
                    title: 'Designation',
                    value: user.designation,
                    color: Colors.purple,
                  ),
                ],
                if (user.department != null && user.department!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildDetailCard(
                    icon: Icons.apartment,
                    title: 'Department',
                    value: user.department!,
                    color: Colors.deepOrange,
                  ),
                ],
                const SizedBox(height: 12),
                if (firstLogin != null) ...[
                  _buildDetailCard(
                    icon: Icons.login,
                    title: 'Created At',
                    value: _formatDateTime(firstLogin),
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 12),
                ],
                if (lastLogin != null)
                  _buildDetailCard(
                    icon: Icons.watch_later,
                    title: 'Last Login',
                    value: _formatDateTime(lastLogin),
                    color: Colors.blue,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
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
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
