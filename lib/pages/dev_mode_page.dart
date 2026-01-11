import 'dart:async';
import 'dart:convert';
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
import '../services/webbridge_service.dart';

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
  bool _showMessagesIn = true;

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

                  // User Information
                  const UserInfoWidget(),
                  const SizedBox(height: 24),

                  // User Sessions
                  const UserSessionsWidget(),
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
                  FutureBuilder<Map<String, dynamic>>(
                    future: DeviceUtils.getDeviceInfo(),
                    builder: (ctx, snap) {
                      final info = snap.data;
                      final model = info?['model'] ?? '-';

                      return Column(
                        children: [
                          _buildDeviceInfoCard(
                            Icons.branding_watermark,
                            'Brand',
                            info?['brand'] ?? '-',
                            Colors.purple,
                          ),
                          const SizedBox(height: 12),
                          _buildDeviceInfoCard(
                            Icons.phone_android,
                            'Model Name',
                            model,
                            Colors.blue,
                          ),
                          const SizedBox(height: 12),
                          _buildDeviceInfoCard(
                            Icons.android,
                            'Android Version',
                            info?['osVersion'] ?? '-',
                            Colors.green,
                          ),
                          const SizedBox(height: 12),
                          _buildDeviceInfoCard(
                            Icons.developer_mode,
                            'SDK Version',
                            info?['sdkVersion'] ?? '-',
                            Colors.orange,
                          ),
                          const SizedBox(height: 12),
                          _buildDeviceInfoCard(
                            Icons.fingerprint,
                            'Device ID',
                            info?['deviceId'] ?? sync.deviceId ?? '-',
                            const Color(0xFF5E17EB),
                          ),
                          const SizedBox(height: 12),
                          _buildDeviceInfoCard(
                            Icons.perm_device_information,
                            'Android ID',
                            info?['androidId'] ?? '-',
                            Colors.red,
                          ),
                        ],
                      );
                    },
                  ),
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
                          color: Colors.grey.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ManualControls(),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            CallLogService().testOverlay();
                          },
                          icon: const Icon(Icons.layers_outlined),
                          label: const Text('Test Call Overlay'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Storage Hierarchy
                  const Text(
                    'Storage Hierarchy',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5E17EB),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildStorageHierarchy(context, sync),
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
                          color: Colors.grey.withValues(alpha: 0.1),
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
                            isLiveSelected: _showLiveLogs,
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
                  const SizedBox(height: 24),

                  // WebView Messages
                  const Text(
                    'WebView Messages',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5E17EB),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildWebViewMessages(context, sync),
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
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
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

  Widget _buildStorageHierarchy(BuildContext context, SyncProvider sync) {
    final callBucketCount = StorageService.callBucket.length;
    final syncedBucketCount = StorageService.syncedBucket.length;
    final appLogsCount = StorageService.appLogs.length;
    final metaKeys = StorageService.meta.keys.length;

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
        children: [
          _buildStorageItem(context, 'Hive Storage', const Color(0xFF5E17EB)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Column(
              children: [
                _buildStorageItem(
                  context,
                  'Call Bucket',
                  Colors.blue,
                  count: callBucketCount,
                  isChild: true,
                ),
                const SizedBox(height: 8),
                _buildStorageItem(
                  context,
                  'Synced Bucket',
                  Colors.green,
                  count: syncedBucketCount,
                  isChild: true,
                ),
                const SizedBox(height: 8),
                _buildStorageItem(
                  context,
                  'App Logs',
                  Colors.orange,
                  count: appLogsCount,
                  isChild: true,
                ),
                const SizedBox(height: 8),
                _buildStorageItem(
                  context,
                  'Meta Box',
                  Colors.purple,
                  count: metaKeys,
                  isChild: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageItem(
    BuildContext context,
    String label,
    Color color, {
    int? count,
    bool isChild = false,
  }) {
    IconData icon;
    if (label == 'Hive Storage') {
      icon = Icons.inbox;
    } else if (label == 'Call Bucket') {
      icon = Icons.phone_callback;
    } else if (label == 'Synced Bucket') {
      icon = Icons.cloud_done;
    } else if (label == 'App Logs') {
      icon = Icons.description;
    } else if (label == 'Meta Box') {
      icon = Icons.info;
    } else {
      icon = Icons.storage;
    }

    return GestureDetector(
      onTap: () {
        _showStorageDetails(context, label, color);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: isChild ? 14 : 16,
                  fontWeight: isChild ? FontWeight.normal : FontWeight.w600,
                ),
              ),
            ),
            if (count != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  void _showStorageDetails(BuildContext context, String label, Color color) {
    final box = _getStorageBox(label);
    if (box == null) return;

    final keys = box.keys.toList();
    final items = <String>[];

    for (final key in keys) {
      final value = box.get(key);
      String jsonValue;

      try {
        if (value is Map) {
          jsonValue = JsonEncoder.withIndent('  ').convert(value);
        } else if (value is List) {
          jsonValue = JsonEncoder.withIndent('  ').convert(value);
        } else {
          jsonValue = JsonEncoder.withIndent('  ').convert({'value': value});
        }
      } catch (e) {
        jsonValue = value.toString();
      }

      items.add('Key: $key\n\n$jsonValue');
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: const BoxConstraints(maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getIconForLabel(label),
                        color: color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text(
                          'No data found',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: color.withValues(alpha: 0.2),
                              ),
                            ),
                            child: SelectableText(
                              items[i],
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                height: 1.4,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  dynamic _getStorageBox(String label) {
    if (label == 'Call Bucket') {
      return StorageService.callBucket;
    } else if (label == 'Synced Bucket') {
      return StorageService.syncedBucket;
    } else if (label == 'App Logs') {
      return StorageService.appLogs;
    } else if (label == 'Meta Box') {
      return StorageService.meta;
    }
    return null;
  }

  IconData _getIconForLabel(String label) {
    if (label == 'Hive Storage') {
      return Icons.inbox;
    } else if (label == 'Call Bucket') {
      return Icons.phone_callback;
    } else if (label == 'Synced Bucket') {
      return Icons.cloud_done;
    } else if (label == 'App Logs') {
      return Icons.description;
    } else if (label == 'Meta Box') {
      return Icons.info;
    }
    return Icons.storage;
  }

  Widget _buildWebViewMessages(BuildContext context, SyncProvider sync) {
    final messagesIn = sync.webViewMessagesIn.reversed.toList();
    final messagesOut = sync.webViewMessagesOut.reversed.toList();

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
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.swap_horiz,
                  color: Color(0xFF5E17EB),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Message Traffic',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                // Connection status indicator
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: WebBridgeService.isConnected
                        ? Colors.green
                        : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 20,
                  ),
                  onPressed: () => sync.clearWebViewMessages(),
                  tooltip: 'Clear messages',
                ),
              ],
            ),
          ),
          SizedBox(
            height: 50,
            child: _WebViewToggleButton(
              showIn: _showMessagesIn,
              inCount: messagesIn.length,
              outCount: messagesOut.length,
              onToggle: (showIn) {
                setState(() {
                  _showMessagesIn = showIn;
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 300,
            child: _showMessagesIn
                ? _buildMessageList(
                    messagesIn,
                    Colors.green,
                    'No incoming messages',
                  )
                : _buildMessageList(
                    messagesOut,
                    Colors.blue,
                    'No outgoing messages',
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(
    List<String> messages,
    Color color,
    String emptyText,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: messages.isEmpty
          ? Center(
              child: Text(
                emptyText,
                style: const TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              itemCount: messages.length,
              itemBuilder: (context, i) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: color.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: SelectableText(
                    messages[i],
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.black87,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _WebViewToggleButton extends StatelessWidget {
  final bool showIn;
  final int inCount;
  final int outCount;
  final Function(bool showIn) onToggle;

  const _WebViewToggleButton({
    required this.showIn,
    required this.inCount,
    required this.outCount,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonWidth = constraints.maxWidth;
        final tabWidth = (buttonWidth - 8) / 2;

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
                alignment: showIn
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: Container(
                  width: tabWidth,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5E17EB),
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
              Row(
                children: [
                  _buildTab(
                    width: tabWidth,
                    label: "IN ($inCount)",
                    selected: showIn,
                    onTap: () => onToggle(true),
                  ),
                  _buildTab(
                    width: tabWidth,
                    label: "OUT ($outCount)",
                    selected: !showIn,
                    onTap: () => onToggle(false),
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
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF5E17EB),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class LogsToggleButton extends StatelessWidget {
  final bool isLiveSelected;
  final Function(bool isLive) onToggle;

  const LogsToggleButton({
    super.key,
    required this.isLiveSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonWidth = constraints.maxWidth;
        final tabWidth = (buttonWidth - 8) / 2;

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
                    color: const Color(0xFF5E17EB),
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
              Row(
                children: [
                  _buildTab(
                    width: tabWidth,
                    icon: Icons.storage_rounded,
                    label: "Persisted",
                    selected: !isLiveSelected,
                    onTap: () => onToggle(false),
                  ),
                  _buildTab(
                    width: tabWidth,
                    icon: Icons.live_tv_rounded,
                    label: "Live",
                    selected: isLiveSelected,
                    onTap: () => onToggle(true),
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
