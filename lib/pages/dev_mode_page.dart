import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/sync_provider.dart';
import '../widgets/logs_console.dart';
import '../widgets/log_viewer.dart';
import '../widgets/manual_controls.dart';
import '../widgets/sync_display.dart';
import '../widgets/user_info_widget.dart';
import '../widgets/user_sessions_widget.dart';
import '../services/call_log_service.dart';
import '../utils/device_utils.dart';
import '../services/storage_service.dart';

class DevModePage extends StatefulWidget {
  const DevModePage({super.key});

  @override
  State<DevModePage> createState() => _DevModePageState();
}

class _DevModePageState extends State<DevModePage> {
  Timer? _countsUpdateTimer;
  late StreamController<bool> _callStatusController;
  late Stream<bool> _callStatusStream;
  Timer? _callStatusTimer;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();
  bool _showLiveLogs = true;

  @override
  void initState() {
    super.initState();

    // Initialize the stream for call status updates
    _callStatusController = StreamController<bool>.broadcast();
    _callStatusStream = _callStatusController.stream;

    // Set up periodic checking of real-time call state
    _callStatusTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_callStatusController.isClosed) return;
      // Access the real-time state directly through the static getter
      _callStatusController.add(CallLogService.isOnCallRealTime);
    });

    // Periodically update counts from storage for live updates
    // Poll faster during sync (every 200ms), slower when idle (every 1s)
    _countsUpdateTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) {
        final sync = context.read<SyncProvider>();
        final pendingCount = StorageService.callBucket.length;
        final syncedCount = StorageService.syncedBucket.length;

        // Update if counts changed
        if (pendingCount != sync.pending || syncedCount != sync.synced) {
          sync.setCounts(pending: pendingCount, synced: syncedCount);
        }

        // Update last sync timestamp if changed
        final lastSyncFromStorage = StorageService.getLastSync();
        if (lastSyncFromStorage != null &&
            (sync.lastSync == null ||
                lastSyncFromStorage.difference(sync.lastSync!).inSeconds.abs() >
                    0)) {
          sync.setLastSync(lastSyncFromStorage);
        }
      }
    });
  }

  @override
  void dispose() {
    _countsUpdateTimer?.cancel();
    _callStatusTimer?.cancel();
    _callStatusController.close();
    super.dispose();
  }

  Future<void> _refreshData() async {
    // Trigger a manual refresh of all data
    final sync = context.read<SyncProvider>();
    final pendingCount = StorageService.callBucket.length;
    final syncedCount = StorageService.syncedBucket.length;
    sync.setCounts(pending: pendingCount, synced: syncedCount);

    final lastSyncFromStorage = StorageService.getLastSync();
    if (lastSyncFromStorage != null) {
      sync.setLastSync(lastSyncFromStorage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Dashboard'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF5E17EB),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: RefreshIndicator(
        key: _refreshIndicatorKey,
        onRefresh: _refreshData,
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Section
                  const Text(
                    'Developer Tools',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5E17EB),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Monitor and control application status',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),

                  // Status Cards Grid
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatusCard(
                          'Device',
                          Icons.devices,
                          sync.deviceId != null ? 'Connected' : 'Offline',
                          sync.deviceId != null ? Colors.green : Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatusCard(
                          'Sync',
                          Icons.sync,
                          sync.isSyncing ? 'Active' : 'Idle',
                          sync.isSyncing ? Colors.blue : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StreamBuilder<bool>(
                          stream: _callStatusStream,
                          initialData: false,
                          builder: (c, s2) {
                            final onCall = s2.data ?? false;
                            return _buildStatusCard(
                              'Call Status',
                              onCall
                                  ? Icons.phone_in_talk
                                  : Icons.phone_disabled,
                              onCall ? 'On Call' : 'Idle',
                              onCall ? Colors.green : Colors.red,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Device Info Card
                  const Text(
                    'Device Information',
                    style: TextStyle(
                      color: Color(0xFF5E17EB),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<Map<String, String>>(
                    future: DeviceUtils.getDeviceInfo(),
                    builder: (ctx, snap) {
                      final info = snap.data;
                      return Column(
                        children: [
                          _buildDeviceInfoCard(
                            Icons.phone_android_outlined,
                            'Device ID',
                            info?['deviceId'] ?? sync.deviceId ?? '-',
                            const Color(0xFF5E17EB),
                          ),
                          const SizedBox(height: 12),
                          _buildDeviceInfoCard(
                            Icons.memory_outlined,
                            'OS',
                            info?['osVersion'] ?? '-',
                            Colors.green,
                          ),
                          const SizedBox(height: 12),
                          _buildDeviceInfoCard(
                            Icons.devices_other_outlined,
                            'Name',
                            info?['deviceName'] ?? '-',
                            Colors.blue,
                          ),
                          const SizedBox(height: 12),
                          _buildDeviceInfoCard(
                            Icons.model_training_outlined,
                            'Model',
                            info?['model'] ?? '-',
                            Colors.orange,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // User Information
                  const UserInfoWidget(),
                  const SizedBox(height: 24),

                  // User Sessions
                  const UserSessionsWidget(),
                  const SizedBox(height: 24),

                  // Sync Status
                  const Text(
                    'Sync Status',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5E17EB),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SyncDisplay(
                    isSyncing: sync.isSyncing,
                    pending: sync.pending,
                    synced: sync.synced,
                    lastSync: sync.lastSync ?? StorageService.getLastSync(),
                  ),
                  const SizedBox(height: 24),

                  // Manual Controls
                  const Text(
                    'Manual Controls',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5E17EB),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: const ManualControls(),
                  ),
                  const SizedBox(height: 24),

                  // Logs Section
                  const Text(
                    'Application Logs',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5E17EB),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: LogsToggleButton(
                            onToggle: (isLive) {
                              setState(() {
                                _showLiveLogs = isLive;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 400,
                          child: _showLiveLogs
                              ? const LogViewer()
                              : const LogsConsole(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(
    String title,
    IconData icon,
    String status,
    Color color,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            status,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceInfoCard(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
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
              color: color.withOpacity(0.1),
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
                  label,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(color: Colors.black54, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LogsToggleButton extends StatefulWidget {
  final Function(bool isLive) onToggle;

  const LogsToggleButton({super.key, required this.onToggle});

  @override
  State<LogsToggleButton> createState() => _LogsToggleButtonState();
}

class _LogsToggleButtonState extends State<LogsToggleButton> {
  bool isLiveSelected = true;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonWidth = constraints.maxWidth;
        final tabWidth =
            (buttonWidth - 8) / 2; // Subtract padding and divide by 2

        return Container(
          width: buttonWidth,
          height: 50,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFF5E17EB), width: 1.5),
            color: Colors.white,
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                alignment: isLiveSelected
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: Container(
                  width: tabWidth,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF5E17EB), Color(0xFF5E17EB)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildTab(
                    width: tabWidth,
                    icon: Icons.storage_rounded,
                    label: "Persisted Logs",
                    selected: !isLiveSelected,
                    onTap: () {
                      setState(() => isLiveSelected = false);
                      widget.onToggle(false);
                    },
                  ),
                  _buildTab(
                    width: tabWidth,
                    icon: Icons.live_tv_rounded,
                    label: "Live Logs",
                    selected: isLiveSelected,
                    onTap: () {
                      setState(() => isLiveSelected = true);
                      widget.onToggle(true);
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTab({
    required double width,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: 42,
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : const Color(0xFF5E17EB),
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF5E17EB),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
