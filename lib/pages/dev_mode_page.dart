import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';
import '../widgets/log_viewer.dart';
import '../widgets/manual_controls.dart';
import '../widgets/update_controls.dart';
import '../widgets/user_sessions_widget.dart';
import '../services/call_log_service.dart';
import '../services/storage_service.dart';
import '../services/webbridge_service.dart';
import 'call_logs_page.dart';
import 'sim_selection_page.dart';
import 'permissions_page.dart';

class DevModePage extends StatefulWidget {
  const DevModePage({super.key});

  @override
  State<DevModePage> createState() => _DevModePageState();
}

class _DevModePageState extends State<DevModePage> with TickerProviderStateMixin {
  int _activeScreen = 0;
  late StreamController<bool> _callStatusController;
  late Stream<bool> _callStatusStream;
  Timer? _callStatusTimer;
  final TextEditingController _urlController = TextEditingController();

  // Colors aligned with CallLogsPage
  static const Color bgColor = Color(0xFFF8F9FE);

  @override
  void initState() {
    super.initState();
    _callStatusController = StreamController<bool>.broadcast();
    _callStatusStream = _callStatusController.stream;

    _callStatusTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_callStatusController.isClosed) return;
      _callStatusController.add(CallLogService.isOnCallRealTime);
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
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
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Stack(
          children: [
            // Screen Content
            Positioned.fill(
              bottom: 74, // Space for Bottom Nav
              child: _buildActiveScreen(),
            ),
            
            // Custom Bottom Nav
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomNav(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveScreen() {
    switch (_activeScreen) {
      case 0: return _OverviewScreen(
        callStatusStream: _callStatusStream,
        onRefresh: _refreshData,
      );
      case 1: return _SignalsScreen(urlController: _urlController);
      case 2: return _StorageScreen();
      case 3: return _ConsoleScreen();
      case 4: return _BridgeScreen();
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildBottomNav() {
    return Container(
      height: 74,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        border: const Border(top: BorderSide(color: Color(0x1A3C2D14))),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard_rounded, label: 'OVERVIEW', isOn: _activeScreen == 0, onTap: () => setState(() => _activeScreen = 0)),
          _NavItem(icon: Icons.wifi_tethering_outlined, activeIcon: Icons.wifi_tethering_rounded, label: 'SIGNALS', isOn: _activeScreen == 1, onTap: () => setState(() => _activeScreen = 1)),
          _NavItem(icon: Icons.storage_outlined, activeIcon: Icons.storage_rounded, label: 'STORAGE', isOn: _activeScreen == 2, onTap: () => setState(() => _activeScreen = 2)),
          _NavItem(icon: Icons.terminal_outlined, activeIcon: Icons.terminal_rounded, label: 'CONSOLE', isOn: _activeScreen == 3, onTap: () => setState(() => _activeScreen = 3)),
          _NavItem(icon: Icons.hub_outlined, activeIcon: Icons.hub_rounded, label: 'BRIDGE', isOn: _activeScreen == 4, onTap: () => setState(() => _activeScreen = 4)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  NAV ITEM WIDGET
// ---------------------------------------------------------------------------
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isOn;
  final VoidCallback onTap;

  const _NavItem({required this.icon, required this.activeIcon, required this.label, required this.isOn, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const Color primary = Color(0xFF5E17EB);
    const Color inactive = Color(0xFF8C7D68);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minWidth: 64),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isOn ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(isOn ? activeIcon : icon, color: isOn ? primary : inactive, size: 22),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: isOn ? primary : inactive,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  OVERVIEW SCREEN
// ---------------------------------------------------------------------------
class _OverviewScreen extends StatefulWidget {
  final Stream<bool> callStatusStream;
  final Future<void> Function() onRefresh;

  const _OverviewScreen({required this.callStatusStream, required this.onRefresh});

  @override
  State<_OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<_OverviewScreen> {
  bool _isUserExpanded = false;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    const Color primary = Color(0xFF5E17EB);

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      displacement: 20,
      color: primary,
      backgroundColor: Colors.white,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(sync),
            
            // Stat Strip
            _buildStatStrip(sync),
            
            // Rings Row (Status Indicators)
            _buildRingsRow(sync),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: const Text('Device Connectivity', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),

            // SIM Hero Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildSimHero(context, sync),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: const Text('Software Update', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),

            // Update Controls
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: UpdateControls(),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SyncProvider sync) {
    const Color primary = Color(0xFF5E17EB);
    final user = sync.user;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SYSTEM CONSOLE', style: TextStyle(fontFamily: 'Roboto', color: Colors.white60, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('Rynxly CRM', style: TextStyle(fontFamily: 'Roboto', color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                child: const Row(
                  children: [
                    CircleAvatar(radius: 2, backgroundColor: Colors.greenAccent),
                    SizedBox(width: 6),
                    Text('v3.0.4', style: TextStyle(fontFamily: 'Roboto', color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          
          // User Card (Expandable)
          InkWell(
            onTap: () => setState(() => _isUserExpanded = !_isUserExpanded),
            borderRadius: BorderRadius.circular(22),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10))],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFF0E7FF),
                          border: Border.all(color: primary.withValues(alpha: 0.1), width: 2),
                          image: user?.profilePicUrl != null 
                            ? DecorationImage(image: NetworkImage(user!.profilePicUrl!), fit: BoxFit.cover)
                            : null,
                        ),
                        child: user?.profilePicUrl == null 
                          ? Center(child: Text(user?.userName.substring(0, 1).toUpperCase() ?? 'U', style: const TextStyle(color: primary, fontSize: 20, fontWeight: FontWeight.bold)))
                          : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user?.userName ?? 'Developer Mode', style: const TextStyle(color: Color(0xFF1C1710), fontSize: 16, fontWeight: FontWeight.bold)),
                            Text(user?.employeeId ?? 'ID: 000000', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      ),
                      Icon(
                        _isUserExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: _isUserExpanded && user != null
                      ? Column(
                          children: [
                            const Divider(height: 24, thickness: 0.5),
                            _buildUserDetailRow(Icons.email_outlined, 'Email', user.email),
                            _buildUserDetailRow(Icons.badge_outlined, 'Role', user.role),
                            _buildUserDetailRow(Icons.work_outline_rounded, 'Designation', user.designation),
                            if (user.department != null) _buildUserDetailRow(Icons.business_outlined, 'Department', user.department!),
                            _buildUserDetailRow(Icons.corporate_fare_rounded, 'Organization', user.organizationId ?? 'N/A'),
                          ],
                        )
                      : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserDetailRow(IconData icon, String label, String value) {
    const Color primary = Color(0xFF5E17EB);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: primary.withValues(alpha: 0.6)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              Text(value, style: const TextStyle(fontSize: 13, color: Color(0xFF1C1710), fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatStrip(SyncProvider sync) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Row(
        children: [
          _StatCell(num: sync.synced.toString(), tag: 'SYNCED', color: const Color(0xFF5E17EB)),
          const SizedBox(width: 12),
          _StatCell(num: sync.pending.toString(), tag: 'PENDING', color: Colors.orange),
          const SizedBox(width: 12),
          _StatCell(num: sync.allLogs.length.toString(), tag: 'LOGS', color: Colors.blue),
        ],
      ),
    );
  }

  Widget _buildRingsRow(SyncProvider sync) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Row(
        children: [
          _RingCard(label: 'DEVICE', val: sync.deviceId != null ? 'ACTIVE' : 'OFFLINE', progress: sync.deviceId != null ? 1.0 : 0.0, color: Colors.green, icon: Icons.smartphone_rounded),
          _RingCard(label: 'BRIDGE', val: WebBridgeService.isConnected ? 'READY' : 'WAITING', progress: WebBridgeService.isConnected ? 1.0 : 0.3, color: const Color(0xFF5E17EB), icon: Icons.hub_rounded),
          _RingCard(label: 'SYNC', val: sync.isSyncing ? 'ACTIVE' : 'IDLE', progress: sync.isSyncing ? 0.8 : 1.0, color: Colors.blue, icon: Icons.sync_rounded),
          StreamBuilder<bool>(
            stream: widget.callStatusStream,
            initialData: false,
            builder: (c, s) {
              final onCall = s.data ?? false;
              return _RingCard(label: 'LINE', val: onCall ? 'BUSY' : 'FREE', progress: onCall ? 0.9 : 1.0, color: onCall ? Colors.red : Colors.teal, icon: onCall ? Icons.phone_in_talk_rounded : Icons.phone_callback_rounded);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSimHero(BuildContext context, SyncProvider sync) {
    final selectedSim = sync.availableSims.firstWhere(
      (s) => s['id']?.toString() == sync.defaultSimId?.toString(),
      orElse: () => {},
    );
    const Color primary = Color(0xFF5E17EB);

    return InkWell(
      onTap: () => Navigator.push(
        context, 
        MaterialPageRoute(builder: (_) => const SimSelectionPage(isFromSettings: true))
      ).then((_) => sync.refreshSims()),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(24), 
          border: Border.all(color: primary.withValues(alpha: 0.1)),
          boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(width: 52, height: 52, decoration: BoxDecoration(color: const Color(0xFFF0E7FF), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.sim_card_rounded, color: primary, size: 26)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ACTIVE SIM INTERFACE', style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                      Text(
                        selectedSim['label'] ?? selectedSim['displayName'] ?? selectedSim['carrierName'] ?? 'Select SIM Card', 
                        style: const TextStyle(color: Color(0xFF1C1710), fontSize: 18, fontWeight: FontWeight.bold)
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _SimStat(val: selectedSim['slotIndex']?.toString() ?? '-', lbl: 'SLOT'),
                _SimStat(val: selectedSim['mcc'] ?? '-', lbl: 'MCC'),
                _SimStat(val: selectedSim['mnc'] ?? '-', lbl: 'MNC'),
                _SimStat(val: 'v4.2', lbl: 'PROTOCOL', isLast: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  SIGNALS SCREEN
// ---------------------------------------------------------------------------
class _SignalsScreen extends StatelessWidget {
  final TextEditingController urlController;
  const _SignalsScreen({required this.urlController});

  @override
  Widget build(BuildContext context) {
    const Color primary = Color(0xFF5E17EB);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Signals & Logic', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                    Text('Native bridge & manual triggers', style: TextStyle(color: Color(0xFF8C7D68), fontSize: 14)),
                  ],
                ),
                IconButton.filled(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PermissionsPage())),
                  icon: const Icon(Icons.security_rounded),
                  style: IconButton.styleFrom(backgroundColor: primary.withValues(alpha: 0.1), foregroundColor: primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // URL Float Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20)]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('WEBVIEW CONTROL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: primary)),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(color: const Color(0xFFF8F9FE), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black.withValues(alpha: 0.05))),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: urlController,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(border: InputBorder.none, hintText: 'Enter debug URL...', icon: Icon(Icons.link, size: 18, color: primary)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => WebBridgeService.updateUrl(urlController.text),
                      style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), padding: const EdgeInsets.all(18), elevation: 0),
                      child: const Text('UPDATE BRIDGE ENDPOINT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: ManualControls(),
          ),
          const SizedBox(height: 32),
          
          // Action Cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CallLogsPage())),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: const Color(0xFFF0E7FF), borderRadius: BorderRadius.circular(24)),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, color: primary, size: 32),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Call History', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1C1710))),
                        Text('Inspect native telephony logs', style: TextStyle(color: primary, fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: primary, size: 16),
                ],
              ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Permissions Manager Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PermissionsPage())),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD), 
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security_rounded, color: Colors.blue, size: 32),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('System Permissions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1C1710))),
                          Text('Manage location, phone & background access', style: TextStyle(color: Colors.blue[700], fontSize: 12, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, color: Colors.blue[700], size: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  STORAGE SCREEN
// ---------------------------------------------------------------------------
class _StorageScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Storage Vault', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                    Text('Local buckets & user sessions', style: TextStyle(color: Color(0xFF8C7D68), fontSize: 14)),
                  ],
                ),
                IconButton.filled(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PermissionsPage())),
                  icon: const Icon(Icons.security_rounded),
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFF5E17EB).withValues(alpha: 0.1), foregroundColor: const Color(0xFF5E17EB)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Storage Grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.1,
              children: [
                _StorageGridCard(label: 'PENDING CALLS', count: StorageService.callBucket.length, color: const Color(0xFF5E17EB), icon: Icons.phone_callback_rounded, box: StorageService.callBucket),
                _StorageGridCard(label: 'SYNCED HISTORY', count: StorageService.syncedBucket.length, color: Colors.blue, icon: Icons.history_rounded, box: StorageService.syncedBucket),
                _StorageGridCard(label: 'FAILED LEADS', count: StorageService.failedBucket.length, color: Colors.red, icon: Icons.error_outline_rounded, box: StorageService.failedBucket),
                _StorageGridCard(label: 'SYSTEM LOGS', count: StorageService.appLogs.length, color: Colors.orange, icon: Icons.terminal_rounded, box: StorageService.appLogs),
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: UserSessionsWidget(),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  CONSOLE SCREEN
// ---------------------------------------------------------------------------
class _ConsoleScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Watch sync provider to force rebuild when logs or filters change
    final sync = context.watch<SyncProvider>();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Console Engine', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                  Text('Live system execution logs', style: TextStyle(color: Color(0xFF8C7D68), fontSize: 14)),
                ],
              ),
              IconButton(
                onPressed: () {
                  sync.clearLogs();
                  // No SnackBar here to keep it fast and responsive if user wants instant feedback
                },
                icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 28),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Expanded(child: LogViewer()),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  BRIDGE SCREEN (NEW)
// ---------------------------------------------------------------------------
class _BridgeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    const Color primary = Color(0xFF5E17EB);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Web Bridge', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                  Text('WebView message stream', style: TextStyle(color: Color(0xFF8C7D68), fontSize: 14)),
                ],
              ),
              IconButton(
                onPressed: () {
                  sync.clearWebViewMessages();
                },
                icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 28),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: sync.webViewMessages.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.hub_outlined, size: 48, color: Colors.grey[300]), const SizedBox(height: 16), Text('No bridge activity yet', style: TextStyle(color: Colors.grey[400]))]))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                itemCount: sync.webViewMessages.length,
                separatorBuilder: (context, i) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final item = sync.webViewMessages[sync.webViewMessages.length - 1 - i];
                  final String msg = item['message']?.toString() ?? '';
                  final String type = item['type']?.toString() ?? 'IN';
                  final String time = item['timestamp']?.toString().split('T').last.substring(0, 5) ?? '';
                  final bool isOut = type == 'OUT';

                  return Row(
                    mainAxisAlignment: isOut ? MainAxisAlignment.end : MainAxisAlignment.start,
                    children: [
                      if (!isOut) _buildTypeIndicator(type),
                      Flexible(
                        child: Container(
                          margin: EdgeInsets.only(left: isOut ? 60 : 8, right: isOut ? 8 : 60),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isOut ? primary : const Color(0xFFF0F4FF),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isOut ? 16 : 0),
                              bottomRight: Radius.circular(isOut ? 0 : 16),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg, 
                                style: TextStyle(fontSize: 13, color: isOut ? Colors.white : const Color(0xFF1C1710), height: 1.4)
                              ),
                              const SizedBox(height: 4),
                              Text(
                                time, 
                                style: TextStyle(fontSize: 9, color: isOut ? Colors.white70 : Colors.grey[500], fontWeight: FontWeight.bold)
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isOut) _buildTypeIndicator(type),
                    ],
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _buildTypeIndicator(String type) {
    final bool isOut = type == 'OUT';
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isOut ? const Color(0xFF5E17EB).withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
      ),
      child: Center(
        child: Icon(
          isOut ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, 
          size: 14, 
          color: isOut ? const Color(0xFF5E17EB) : Colors.blue
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  HELPER UI COMPONENTS
// ---------------------------------------------------------------------------
class _StatCell extends StatelessWidget {
  final String num;
  final String tag;
  final Color color;
  const _StatCell({required this.num, required this.tag, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 10)],
        ),
        child: Column(
          children: [
            Text(num, style: TextStyle(fontSize: 24, color: color, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(tag, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

class _RingCard extends StatelessWidget {
  final String label;
  final String val;
  final double progress;
  final Color color;
  final IconData icon;

  const _RingCard({required this.label, required this.val, required this.progress, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      width: 110,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)]),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(width: 56, height: 56, child: CircularProgressIndicator(value: progress, strokeWidth: 6, backgroundColor: const Color(0xFFF8F9FE), color: color, strokeCap: StrokeCap.round)),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 16),
          Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1C1710))),
        ],
      ),
    );
  }
}

class _SimStat extends StatelessWidget {
  final String val;
  final String lbl;
  final bool isLast;
  const _SimStat({required this.val, required this.lbl, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: isLast ? null : Border(right: BorderSide(color: Colors.black.withValues(alpha: 0.05)))),
        child: Column(
          children: [
            Text(val, style: const TextStyle(color: Color(0xFF1C1710), fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(lbl, style: const TextStyle(color: Colors.grey, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          ],
        ),
      ),
    );
  }
}

class _StorageGridCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  final Box box;

  const _StorageGridCard({required this.label, required this.count, required this.color, required this.icon, required this.box});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context, 
        isScrollControlled: true, 
        backgroundColor: Colors.transparent, 
        builder: (_) => StorageInspectorModal(title: label, box: box)
      ),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: color.withValues(alpha: 0.1))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 20)),
            const Spacer(),
            Text(count.toString(), style: TextStyle(fontSize: 26, color: color, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

class StorageInspectorModal extends StatelessWidget {
  final String title;
  final Box box;

  const StorageInspectorModal({super.key, required this.title, required this.box});

  @override
  Widget build(BuildContext context) {
    final keys = box.keys.toList().reversed.toList();
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FE),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    Text('${keys.length} entries found', style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.grey),
                  style: IconButton.styleFrom(backgroundColor: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1, color: Color(0x0D000000)),
          Expanded(
            child: keys.isEmpty
              ? Center(child: Text('No data in this bucket', style: TextStyle(color: Colors.grey[400], fontSize: 14)))
              : ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: keys.length,
                  separatorBuilder: (context, i) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final key = keys[i];
                    final dynamic value = box.get(key);
                    
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('KEY: $key', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const Spacer(),
                              const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF5E17EB)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            value.toString(),
                            style: const TextStyle(fontSize: 12, color: Color(0xFF1C1710)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}
