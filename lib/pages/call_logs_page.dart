import 'package:flutter/material.dart';
import 'package:call_log/call_log.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:async';
import '../services/storage_service.dart';
import '../utils/phone_utils.dart';
import '../services/call_log_service.dart';
import '../services/sync_service.dart';

class CallLogsPage extends StatefulWidget {
  const CallLogsPage({super.key});
  @override
  State<CallLogsPage> createState() => _CallLogsPageState();
}


class _CallLogsPageState extends State<CallLogsPage> {
  List<CallLogEntry> _allLogs = [];
  List<CallLogEntry> _filteredLogs = [];
  bool _isLoading = true;
  
  // Filters
  DateTime _selectedDate = DateTime.now();
  String _selectedType = 'All'; // All, Incoming, Outgoing, Missed
  String _selectedCategory = 'All'; // All, Personal, Customer
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _fetchCallLogs();
    _searchController.addListener(_applyFilters);
    
    // 🛰️ REAL-TIME UPDATE: Listen for sync events to refresh the UI
    _syncSubscription = SyncService.syncEvents.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCallLogs() async {
    setState(() => _isLoading = true);
    
    // Set range to start and end of selected day
    final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 0, 0, 0);
    final endOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);
    
    try {
      final Iterable<CallLogEntry> entries = await CallLog.query(
        dateFrom: startOfDay.millisecondsSinceEpoch,
        dateTo: endOfDay.millisecondsSinceEpoch,
      );
      
      _allLogs = entries.toList();
      _allLogs.sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));
      
      // 🚀 SMART TRIGGER: Enqueue any untracked logs found in this view
      CallLogService().enqueueUntrackedLogs(_allLogs);
      
      _applyFilters();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    
    setState(() {
      _filteredLogs = _allLogs.where((log) {
        // 1. Search Query
        final name = (log.name ?? '').toLowerCase();
        final number = (log.number ?? '').toLowerCase();
        bool matchesSearch = query.isEmpty || name.contains(query) || number.contains(query);
        if (!matchesSearch) return false;

        // 2. Call Type
        if (_selectedType != 'All') {
          if (_selectedType == 'Incoming' && log.callType != CallType.incoming) return false;
          if (_selectedType == 'Outgoing' && log.callType != CallType.outgoing) return false;
          if (_selectedType == 'Missed' && log.callType != CallType.missed) return false;
        }

        // 3. Category (Personal vs Customer)
        if (_selectedCategory != 'All') {
          final cleanNumber = PhoneUtils.normalize(log.number ?? '');
          final callId = '${cleanNumber}_${log.timestamp}_${log.duration}';
          final syncedData = StorageService.syncedBucket.get(callId);
          bool isPersonal = true;
          if (syncedData is Map) {
            isPersonal = syncedData['isPersonal'] ?? true;
          }
          
          if (_selectedCategory == 'Personal' && !isPersonal) return false;
          if (_selectedCategory == 'Customer' && isPersonal) return false;
        }

        return true;
      }).toList();
      _isLoading = false;
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF5E17EB)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _fetchCallLogs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Call History', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            ValueListenableBuilder(
              valueListenable: StorageService.syncedBucket.listenable(),
              builder: (context, box, _) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${box.length} Synced',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF5E17EB),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 🔍 SEARCH & FILTERS HEADER
          _buildFilterHeader(),

          // 📊 STATS BAR
          _buildStatsBar(),
          
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredLogs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text('No logs matching filters', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _selectedType = 'All';
                                  _selectedCategory = 'All';
                                  _searchController.clear();
                                });
                                _applyFilters();
                              },
                              child: const Text('Clear Filters'),
                            )
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchCallLogs,
                        color: const Color(0xFF5E17EB),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filteredLogs.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final log = _filteredLogs[index];
                            final cleanNumber = PhoneUtils.normalize(log.number ?? '');
                            final callId = '${cleanNumber}_${log.timestamp}_${log.duration}';
                            
                            final date = DateTime.fromMillisecondsSinceEpoch(log.timestamp ?? 0);
                            final timeStr = DateFormat('h:mm a').format(date);
                            final dateStr = DateFormat('MMM d').format(date);
  
                            return ValueListenableBuilder(
                              // 🔔 REACTIVE BINDING: Rebuild card when sync status changes in Hive
                              valueListenable: StorageService.callBucket.listenable(keys: [callId]),
                              builder: (context, box, _) {
                                return ValueListenableBuilder(
                                  valueListenable: StorageService.syncedBucket.listenable(keys: [callId]),
                                  builder: (context, box, _) {
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                                      ),
                                      child: ListTile(
                                        onTap: () => _showLogDetails(log, callId),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        leading: Stack(
                                          alignment: Alignment.bottomRight,
                                          children: [
                                            CircleAvatar(
                                              backgroundColor: const Color(0xFFF0E7FF),
                                              child: _getUsageIcon(callId),
                                            ),
                                            _getStatusDot(callId),
                                          ],
                                        ),
                                        title: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                log.name?.isNotEmpty == true ? log.name! : (log.number ?? 'Unknown'),
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Text(
                                              _formatDuration(log.duration),
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blueAccent),
                                            ),
                                          ],
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 4),
                                            Text(log.number ?? 'No Number', style: TextStyle(color: Colors.grey.shade600)),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(Icons.access_time, size: 12, color: Colors.grey.shade400),
                                                const SizedBox(width: 4),
                                                Text('$timeStr, $dateStr', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                                const Spacer(),
                                                _getCallTypeLabel(log.callType),
                                                _getCategoryLabel(callId),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterHeader() {
    return Container(
      color: const Color(0xFF5E17EB),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // Search Bar
          TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search by name or number...',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              prefixIcon: const Icon(Icons.search, color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.1),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
          const SizedBox(height: 12),
          // Filter Chips Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Date Selector
                _filterChip(
                  label: DateFormat('MMM d').format(_selectedDate),
                  icon: Icons.calendar_today,
                  onTap: () => _selectDate(context),
                  isActive: true,
                ),
                const SizedBox(width: 8),
                // Type Filter
                _filterMenu(
                  value: _selectedType,
                  items: ['All', 'Incoming', 'Outgoing', 'Missed'],
                  onChanged: (v) {
                    setState(() => _selectedType = v!);
                    _applyFilters();
                  },
                ),
                const SizedBox(width: 8),
                // Category Filter
                _filterMenu(
                  value: _selectedCategory,
                  items: ['All', 'Personal', 'Customer'],
                  onChanged: (v) {
                    setState(() => _selectedCategory = v!);
                    _applyFilters();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    int total = _allLogs.length;
    int customerCount = _allLogs.where((log) {
      final cleanNumber = PhoneUtils.normalize(log.number ?? '');
      final callId = '${cleanNumber}_${log.timestamp}_${log.duration}';
      final syncedData = StorageService.syncedBucket.get(callId);
      if (syncedData is Map) return syncedData['isPersonal'] == false;
      return false;
    }).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          _statItem('Total Calls', total.toString(), Colors.blue),
          const SizedBox(width: 16),
          _statItem('Customer Calls', customerCount.toString(), const Color(0xFF5E17EB)),
          const Spacer(),
          Text(
            DateFormat('EEEE, MMM d').format(_selectedDate),
            style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 10, fontWeight: FontWeight.w500)),
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _filterChip({required String label, required IconData icon, required VoidCallback onTap, bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isActive ? const Color(0xFF5E17EB) : Colors.white70),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: isActive ? const Color(0xFF5E17EB) : Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _filterMenu({required String value, required List<String> items, required ValueChanged<String?> onChanged}) {
    return Container(
      height: 36, // Matches _filterChip height (~8*2 + text_height)
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: const Color(0xFF5E17EB),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds == 0) return '0s';
    final duration = Duration(seconds: seconds);
    final min = duration.inMinutes;
    final sec = duration.inSeconds % 60;
    return min > 0 ? '${min}m ${sec}s' : '${sec}s';
  }

  Widget _getStatusDot(String callId) {
    final syncedData = StorageService.syncedBucket.get(callId);
    final pendingData = StorageService.callBucket.get(callId);
    
    bool isPersonal = true;
    if (syncedData is Map) {
      isPersonal = syncedData['isPersonal'] ?? true;
    } else if (syncedData is String) {
      isPersonal = true;
    } else if (pendingData is Map && pendingData['model'] is Map) {
      isPersonal = pendingData['model']['isPersonal'] ?? true;
    }

    if (syncedData != null) {
      if (isPersonal) return const _StatusDot(color: Colors.grey, tooltip: 'Not Tracked');
      return const _StatusDot(color: Colors.green, tooltip: 'Synced');
    }
    
    if (pendingData != null) {
      final status = pendingData['status'] ?? 'pending';
      if (status == 'failed') return const _StatusDot(color: Colors.red, tooltip: 'Failed');
      return const _StatusDot(color: Colors.orange, tooltip: 'Processing');
    }
    return const _StatusDot(color: Colors.grey, tooltip: 'Not Tracked');
  }

  Widget _getUsageIcon(String callId) {
    final syncedData = StorageService.syncedBucket.get(callId);
    final pendingData = StorageService.callBucket.get(callId);
    bool isPersonal = true;
    
    if (syncedData is Map) {
      isPersonal = syncedData['isPersonal'] ?? true;
    } else if (syncedData is String) {
      isPersonal = true;
    } else if (pendingData is Map && pendingData['model'] is Map) {
      isPersonal = pendingData['model']['isPersonal'] ?? true;
    }

    return Icon(
      isPersonal ? Icons.contact_phone_rounded : Icons.headset_mic_rounded,
      size: 18,
      color: isPersonal ? Colors.blueGrey : const Color(0xFF5E17EB),
    );
  }

  void _showLogDetails(CallLogEntry log, String callId) {
    final syncedData = StorageService.syncedBucket.get(callId);
    final pendingData = StorageService.callBucket.get(callId);
    
    bool isPersonal = true;
    if (syncedData is Map) {
      isPersonal = syncedData['isPersonal'] ?? true;
    } else if (syncedData is String) {
      // Legacy or skipped personal call
      isPersonal = true; 
    } else if (pendingData is Map && pendingData['model'] is Map) {
      isPersonal = pendingData['model']['isPersonal'] ?? true;
    }
    
    Map<String, dynamic>? model;
    String status = 'Unknown';
    
    if (syncedData != null) {
      status = isPersonal ? 'Not Tracked (Personal)' : 'Successfully Synced';
    } else if (pendingData != null) {
      model = pendingData['model'];
      status = pendingData['status'] == 'failed' ? 'Failed' : 'Pending Sync';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),
            const Text('Call Log Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(height: 32),
            _detailRow('Status', status, isStatus: true),
            _detailRow('Number', log.number ?? 'N/A'),
            _detailRow('Name', log.name ?? 'Unknown'),
            _detailRow('Duration', _formatDuration(log.duration)),
            _detailRow('Date', DateFormat('MMM d, y h:mm a').format(DateTime.fromMillisecondsSinceEpoch(log.timestamp ?? 0))),
            _detailRow('Category', isPersonal ? 'Personal' : 'Customer', isCategory: true),
            _detailRow('Unique ID', callId),
            if (model != null) ...[
               _detailRow('Employee ID', model['employee_id'] ?? 'N/A'),
               _detailRow('Device ID', model['device_id'] ?? 'N/A'),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5E17EB),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isStatus = false, bool isCategory = false}) {
    Color textColor = Colors.black87;
    if (isStatus) {
      if (value.contains('Success')) {
        textColor = Colors.green;
      } else if (value.contains('Personal') || value.contains('Not Tracked')) {
        textColor = Colors.grey;
      } else {
        textColor = Colors.orange;
      }
    } else if (isCategory) {
      textColor = value == 'Customer' ? const Color(0xFF5E17EB) : Colors.blueGrey;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 14))),
          Expanded(
            child: Text(
              value, 
              style: TextStyle(
                fontWeight: FontWeight.w600, 
                fontSize: 14,
                color: textColor,
              )
            ),
          ),
        ],
      ),
    );
  }

  Widget _getCategoryLabel(String callId) {
    final syncedData = StorageService.syncedBucket.get(callId);
    final pendingData = StorageService.callBucket.get(callId);
    bool isPersonal = true;
    
    if (syncedData is Map) {
      isPersonal = syncedData['isPersonal'] ?? true;
    } else if (syncedData is String) {
      isPersonal = true;
    } else if (pendingData is Map && pendingData['model'] is Map) {
      isPersonal = pendingData['model']['isPersonal'] ?? true;
    }
    
    final color = isPersonal ? Colors.blueGrey : const Color(0xFF5E17EB);
    final text = isPersonal ? 'Personal' : 'Customer';
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      margin: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _getCallTypeLabel(CallType? type) {
    String text = 'Unknown';
    Color color = Colors.grey;
    switch (type) {
      case CallType.incoming:
      case CallType.wifiIncoming:
        text = 'Incoming';
        color = Colors.blue;
        break;
      case CallType.outgoing:
      case CallType.wifiOutgoing:
        text = 'Outgoing';
        color = Colors.green;
        break;
      case CallType.missed:
      case CallType.rejected:
        text = 'Missed';
        color = Colors.red;
        break;
      case CallType.blocked:
        text = 'Blocked';
        color = Colors.black54;
        break;
      default:
        text = 'Other';
        color = Colors.grey;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  final String tooltip;
  const _StatusDot({required this.color, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }
}
