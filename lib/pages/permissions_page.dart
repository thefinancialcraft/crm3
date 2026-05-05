import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/consent_service.dart';
import 'sim_selection_page.dart';

class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage>
    with WidgetsBindingObserver {
  bool _phoneStateGranted = false;
  bool _contactsGranted = false;
  bool _callPhoneGranted = false;
  bool _notificationsGranted = false;
  bool _overlayGranted = false;
  bool _batteryOptimizationGranted = false;
  bool _locationGranted = false;

  final platform = const MethodChannel('com.example.crm3/main');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAllPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAllPermissions();
    }
  }

  Future<void> _checkAllPermissions() async {
    _phoneStateGranted = await Permission.phone.isGranted;
    _contactsGranted = await Permission.contacts.isGranted;
    _locationGranted = await Permission.location.isGranted;
    // CALL_PHONE and ANSWER_PHONE_CALLS are both under the phone group, but we can check specifically.
    // However, permission_handler maps them both to Permission.phone in most cases.
    _callPhoneGranted = await Permission.phone.isGranted;
    _notificationsGranted = await Permission.notification.isGranted;

    // Check overlay using MethodChannel as requested
    try {
      final bool hasOverlay = await platform.invokeMethod(
        'checkOverlayPermission',
      );
      _overlayGranted = hasOverlay;
    } catch (e) {
      debugPrint("Failed to check overlay: $e");
    }

    // Check battery optimization natively as permission_handler caches the result incorrectly on some OEM devices
    try {
      final bool hasBatteryBypass = await platform.invokeMethod(
        'checkBatteryOptimizationBypass',
      );
      _batteryOptimizationGranted = hasBatteryBypass;
    } catch (e) {
      debugPrint("Failed to check battery optimization natively: $e");
      _batteryOptimizationGranted =
          await Permission.ignoreBatteryOptimizations.isGranted;
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _requestPermission(
    Permission permission,
    VoidCallback onSuccess,
  ) async {
    final status = await permission.request();
    if (status.isGranted) {
      onSuccess();
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    }
    _checkAllPermissions();
  }

  Future<void> _handleOverlayPermission() async {
    try {
      final bool hasPermission = await platform.invokeMethod(
        'checkOverlayPermission',
      );
      if (!hasPermission) {
        await platform.invokeMethod('requestOverlayPermission');
      } else {
        setState(() {
          _overlayGranted = true;
        });
      }
    } catch (e) {
      debugPrint("Failed to request overlay permission: $e");
    }
  }

  Future<void> _handleBatteryOptimization() async {
    // Native request bypasses permission_handler bugs on some OEM devices
    try {
      await platform.invokeMethod('requestBatteryOptimizationBypass');
    } catch (e) {
      debugPrint("Failed to request battery optimization bypass natively: $e");
      // Fallback
      await Permission.ignoreBatteryOptimizations.request();
    }

    // On some devices (Xiaomi, Vivo, Oppo), we also need AutoStart permission
    try {
      await platform.invokeMethod('requestAutoStartPermission');
    } catch (e) {
      debugPrint("Failed to request AutoStart permission: $e");
    }

    _checkAllPermissions();
  }

  bool get _allPermissionsGranted {
    return _phoneStateGranted &&
        _contactsGranted &&
        _callPhoneGranted &&
        _notificationsGranted &&
        _overlayGranted &&
        _batteryOptimizationGranted &&
        _locationGranted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            const Text(
              'Required Permissions',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: const Text(
                'To provide the best CRM experience, we need access to the following features. Please enable all permissions to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  _buildPermissionTile(
                    title: 'Phone State',
                    subtitle: 'To detect incoming and outgoing calls',
                    icon: Icons.phone_android,
                    isGranted: _phoneStateGranted,
                    onTap: () => _requestPermission(Permission.phone, () {}),
                  ),
                  _buildPermissionTile(
                    title: 'Contacts',
                    subtitle: 'To identify callers in the CRM',
                    icon: Icons.contacts,
                    isGranted: _contactsGranted,
                    onTap: () => _requestPermission(Permission.contacts, () {}),
                  ),
                  _buildPermissionTile(
                    title: 'Manage Calls',
                    subtitle: 'To make and disconnect calls directly',
                    icon: Icons.call,
                    isGranted: _callPhoneGranted,
                    onTap: () => _requestPermission(Permission.phone, () {}),
                  ),
                  _buildPermissionTile(
                    title: 'Notifications',
                    subtitle: 'To run securely in the background',
                    icon: Icons.notifications,
                    isGranted: _notificationsGranted,
                    onTap: () =>
                        _requestPermission(Permission.notification, () {}),
                  ),
                  _buildPermissionTile(
                    title: 'Display over other apps',
                    subtitle: 'To show caller details popup on screen',
                    icon: Icons.layers,
                    isGranted: _overlayGranted,
                    onTap: _handleOverlayPermission,
                  ),
                  _buildPermissionTile(
                    title: 'Ignore Battery Optimization',
                    subtitle: 'To prevent the app from sleeping',
                    icon: Icons.battery_charging_full,
                    isGranted: _batteryOptimizationGranted,
                    onTap: _handleBatteryOptimization,
                  ),
                  _buildPermissionTile(
                    title: 'Location Permission',
                    subtitle: 'Required to access SIM carrier info (Android 10+)',
                    icon: Icons.location_on_outlined,
                    isGranted: _locationGranted,
                    onTap: () => _requestPermission(Permission.location, () {}),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _allPermissionsGranted
                      ? () async {
                          await ConsentService.markOnboardingComplete();
                          if (!context.mounted) return;
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => const SimSelectionPage(),
                            ),
                          );
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFF4B33E8),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF4B33E8).withValues(alpha: 0.5),
                    disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Get Started',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isGranted,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isGranted
            ? Colors.green.shade100
            : const Color(0xFF4B33E8).withValues(alpha: 0.1),
        child: Icon(icon, color: isGranted ? Colors.green : const Color(0xFF4B33E8)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: Switch(
        value: isGranted,
        onChanged: (val) {
          if (!isGranted && val) {
            onTap();
          }
        },
        activeThumbColor: Colors.green,
      ),
      onTap: isGranted ? null : onTap,
    );
  }
}
