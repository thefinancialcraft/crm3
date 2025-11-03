import 'package:flutter/material.dart';

class UserSessionsWidget extends StatelessWidget {
  const UserSessionsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // Dummy past user data
    final pastUsers = [
      {
        'id': 'USR001',
        'name': 'John Developer',
        'firstLogin': DateTime.now().subtract(const Duration(days: 30)),
        'lastLogin': DateTime.now().subtract(const Duration(hours: 2)),
        'lastLogout': DateTime.now().subtract(const Duration(hours: 3)),
      },
      {
        'id': 'USR002',
        'name': 'Jane Tester',
        'firstLogin': DateTime.now().subtract(const Duration(days: 15)),
        'lastLogin': DateTime.now().subtract(const Duration(days: 1)),
        'lastLogout': DateTime.now().subtract(const Duration(days: 1, hours: 2)),
      },
      {
        'id': 'USR003',
        'name': 'Mike Admin',
        'firstLogin': DateTime.now().subtract(const Duration(days: 45)),
        'lastLogin': DateTime.now().subtract(const Duration(hours: 24)),
        'lastLogout': DateTime.now().subtract(const Duration(hours: 26)),
      },
    ];

    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Past User Sessions',
            style: TextStyle(
              color: Color(0xFF5E17EB),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          
          // Horizontal ScrollView for the table
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
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
              child: Column(
                children: [
                  // Table Header with modern styling
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF5E17EB),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: Text(
                            'User ID',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: Text(
                            'User',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 150,
                          child: Text(
                            'First Login',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 150,
                          child: Text(
                            'Last Login',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 150,
                          child: Text(
                            'Last Logout',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Table Rows with modern styling
                  ...List.generate(pastUsers.length, (index) {
                    final user = pastUsers[index];
                    final isLast = index == pastUsers.length - 1;
                    return Container(
                      decoration: BoxDecoration(
                        border: isLast
                            ? null
                            : Border(
                                bottom: BorderSide(
                                  color: Colors.grey.shade200,
                                  width: 0.5,
                              ),
                            ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: Text(
                              user['id'] as String,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Text(
                              user['name'] as String,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: Text(
                              _formatDateTime(user['firstLogin'] as DateTime),
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: Text(
                              _formatDateTime(user['lastLogin'] as DateTime),
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: Text(
                              _formatDateTime(user['lastLogout'] as DateTime),
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
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