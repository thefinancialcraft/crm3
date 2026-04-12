import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import '../providers/sync_provider.dart';
import '../widgets/log_viewer.dart';
import '../widgets/manual_controls.dart';
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

class _DevModePageState extends State<DevModePage> with SingleTickerProviderStateMixin {
  late StreamController<bool> _callStatusController;
  late Stream<bool> _callStatusStream;
  Timer? _callStatusTimer;
  late TabController _tabController;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _callStatusController = StreamController<bool>.broadcast();
    _callStatusStream = _callStatusController.stream;

    _callStatusTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_callStatusController.isClosed) return;
      _callStatusController.add(CallLogService.isOnCallRealTime);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _callStatusTimer?.cancel();
    _callStatusController.close();
    super.dispose();
  }

  Future<void> _refreshData() async {
    final sync = context.read<SyncProvider>();
    await sync.refreshSims();
    sync.refreshPersistedLogs();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF5E17EB);
    const bgColor = Color(0xFFF8F9FE);

    return Scaffold(
      backgroundColor: bgColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 120,
            floating: true,
            pinned: true,
            elevation: 0,
            backgroundColor: primaryColor,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text('Developer Console', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [primaryColor, Color(0xFF8C52FF)],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _refreshData),
            ],
          ),
        ],
        body: RefreshIndicator(
          key: _refreshIndicatorKey,
          onRefresh: _refreshData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Status Grid (2x2)
                _buildStatusGrid(context),
                const SizedBox(height: 24),

                // 2. SIM Selector (ValueListenable for Zero-Lag Reactivity)
                ValueListenableBuilder(
                  valueListenable: StorageService.meta.listenable(keys: ['defaultSimId']),
                  builder: (context, box, child) {
                    final sync = context.watch<SyncProvider>();
                    return ModernSimCard(
                      sync: sync,
                      onTap: () => _showSimSelectorModel(context, sync),
                    );
                  },
                ),
                const SizedBox(height: 24),

                // 3. Main Info Tabs
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    children: [
                      TabBar(
                        controller: _tabController,
                        labelColor: primaryColor,
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: primaryColor,
                        indicatorSize: TabBarIndicatorSize.label,
                        dividerColor: Colors.transparent,
                        tabs: const [
                          Tab(text: 'System'),
                          Tab(text: 'Signals'),
                          Tab(text: 'Storage'),
                        ],
                      ),
                      SizedBox(
                        height: 420,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildSystemTab(),
                            _buildSignalsTab(),
                            _buildStorageTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 4. Live Logs Section (Always Visible or Link)
                const SectionHeader(title: 'Live Output'),
                const SizedBox(height: 12),
                _buildLogsConsole(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusGrid(BuildContext context) {
    return Consumer<SyncProvider>(
      builder: (context, sync, _) {
        return GridView.count(
          shrinkWrap: true,
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.6,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            CompactStatusCard(
              title: 'Device',
              value: sync.deviceId != null ? 'Active' : 'Offline',
              icon: Icons.smartphone_rounded,
              color: sync.deviceId != null ? Colors.green : Colors.orange,
              onTap: () {},
            ),
            CompactStatusCard(
              title: 'Sync',
              value: sync.isSyncing ? 'Syncing...' : 'Idle',
              icon: Icons.sync_rounded,
              color: sync.isSyncing ? const Color(0xFF5E17EB) : Colors.blueGrey,
              onTap: () => sync.refreshCounts(),
            ),
            StreamBuilder<bool>(
              stream: _callStatusStream,
              initialData: false,
              builder: (c, s2) {
                final onCall = s2.data ?? false;
                return CompactStatusCard(
                  title: 'Line',
                  value: onCall ? 'Busy' : 'Available',
                  icon: onCall ? Icons.phone_in_talk_rounded : Icons.phone_callback_rounded,
                  color: onCall ? Colors.redAccent : Colors.teal,
                  onTap: () {},
                );
              },
            ),
            CompactStatusCard(
              title: 'Bridge',
              value: WebBridgeService.isConnected ? 'Connected' : 'Disconnected',
              icon: Icons.hub_rounded,
              color: WebBridgeService.isConnected ? Colors.indigo : Colors.deepOrange,
              onTap: () {},
            ),
          ],
        );
      },
    );
  }

  Widget _buildSystemTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const UserInfoWidget(),
          const SizedBox(height: 16),
          const ModernDivider(),
          const SizedBox(height: 16),
          FutureBuilder<Map<String, dynamic>>(
            future: DeviceUtils.getDeviceInfo(),
            builder: (ctx, snap) {
              final info = snap.data ?? {};
              return Column(
                children: [
                  InfoRow(label: 'Manufacturer', value: info['brand'] ?? '-'),
                  InfoRow(label: 'Model', value: info['model'] ?? '-'),
                  InfoRow(label: 'Android', value: info['osVersion'] ?? '-'),
                  InfoRow(label: 'API Level', value: info['sdkVersion'] ?? '-'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSignalsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SectionTitle(title: 'WebView Message Stream'),
          const SizedBox(height: 12),
          _buildCompactWebViewMessages(),
          const SizedBox(height: 20),
          const ModernDivider(),
          const SizedBox(height: 20),
          const ManualControls(),
        ],
      ),
    );
  }

  Widget _buildStorageTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const UserSessionsWidget(),
          const SizedBox(height: 20),
          const ModernDivider(),
          const SizedBox(height: 20),
          _buildCompactStorageInfo(),
        ],
      ),
    );
  }

  Widget _buildCompactWebViewMessages() {
    return Consumer<SyncProvider>(
      builder: (context, sync, _) {
        final messagesIn = sync.webViewMessagesIn.length;
        final messagesOut = sync.webViewMessagesOut.length;
        return Row(
          children: [
            Expanded(child: MessageCountCard(label: 'Incoming', count: messagesIn, color: Colors.green)),
            const SizedBox(width: 12),
            Expanded(child: MessageCountCard(label: 'Outgoing', count: messagesOut, color: Colors.blue)),
          ],
        );
      },
    );
  }

  Widget _buildCompactStorageInfo() {
    return Column(
      children: [
        StorageMiniRow(label: 'Calls (Pending)', count: StorageService.callBucket.length, color: Colors.blue),
        StorageMiniRow(label: 'Synced History', count: StorageService.syncedBucket.length, color: Colors.green),
        StorageMiniRow(label: 'App Logs', count: StorageService.appLogs.length, color: Colors.orange),
      ],
    );
  }

  Widget _buildLogsConsole() {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: const LogViewer(),
    );
  }

  void _showSimSelectorModel(BuildContext context, SyncProvider _) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const ModernSimModal(),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader({super.key, required this.title});
  @override
  Widget build(BuildContext context) {
    return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87, letterSpacing: -0.5));
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  const SectionTitle({super.key, required this.title});
  @override
  Widget build(BuildContext context) {
    return Align(alignment: Alignment.centerLeft, child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)));
  }
}

class CompactStatusCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const CompactStatusCard({super.key, required this.title, required this.value, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5, offset: const Offset(0, 2))],
          border: Border.all(color: color.withValues(alpha: 0.1), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ModernSimCard extends StatelessWidget {
  final SyncProvider sync;
  final VoidCallback onTap;

  const ModernSimCard({super.key, required this.sync, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selectedSim = sync.availableSims.firstWhere(
      (s) => s['id']?.toString() == sync.defaultSimId?.toString(),
      orElse: () => {},
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF5E17EB), Color(0xFF7B3FFF)]),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: const Color(0xFF5E17EB).withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 8))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.sim_card_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Duo-SIM Routing', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(selectedSim['label'] ?? 'System Default (Ask)', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

class ModernSimModal extends StatelessWidget {
  const ModernSimModal({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SyncProvider>(
      builder: (context, sync, _) => Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('SIM Preferences', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => sync.refreshSims()),
              ],
            ),
            const SizedBox(height: 16),
            ...sync.availableSims.map((sim) {
              final id = sim['id']?.toString();
              final isSelected = sync.defaultSimId == id;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF5E17EB).withValues(alpha: 0.04) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isSelected ? const Color(0xFF5E17EB) : Colors.grey.shade200, width: 2),
                ),
                child: RadioListTile<String?>(
                  title: Text(sim['label'] ?? 'Unknown', style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? const Color(0xFF5E17EB) : Colors.black87)),
                  subtitle: Text('ID: ${sim['id']} • Slot ${sim['slotIndex']}'),
                  value: id,
                  groupValue: sync.defaultSimId,
                  onChanged: (v) { sync.setDefaultSim(v); Navigator.pop(context); },
                  activeColor: const Color(0xFF5E17EB),
                ),
              );
            }),
            const SizedBox(height: 8),
            ListTile(
              title: const Text('Ask Every Time', style: TextStyle(fontWeight: FontWeight.w500)),
              leading: const Icon(Icons.tune_rounded),
              trailing: sync.defaultSimId == null ? const Icon(Icons.check_circle, color: Colors.green) : null,
              onTap: () { sync.setDefaultSim(null); Navigator.pop(context); },
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade200)),
            ),
          ],
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const InfoRow({super.key, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 13)),
        ],
      ),
    );
  }
}

class MessageCountCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const MessageCountCard({super.key, required this.label, required this.count, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.1))),
      child: Column(children: [Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(count.toString(), style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold))]),
    );
  }
}

class StorageMiniRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const StorageMiniRow({super.key, required this.label, required this.count, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [Icon(Icons.folder_open_rounded, color: color, size: 18), const SizedBox(width: 12), Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))), Text(count.toString(), style: TextStyle(color: color, fontWeight: FontWeight.bold))]),
    );
  }
}

class ModernDivider extends StatelessWidget {
  const ModernDivider({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: Colors.grey.withValues(alpha: 0.08));
  }
}
