import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/sync_provider.dart';
import 'utils/device_utils.dart';
import 'services/notification_service.dart';
import 'services/call_log_service.dart';
import 'pages/inapp_webview_page.dart';
import 'widgets/connection_wrapper.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // Initialize notifications first
    await NotificationService.initialize();

    // Initialize call log service
    final callSvc = CallLogService();
    await callSvc.initializeCallStateListener();
  }

  @override
  Widget build(BuildContext context) {
    // Defer the device ID setup to after the build phase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureDeviceId(context);
    });

    // Show InAppWebViewPage wrapped with ConnectionWrapper to handle offline state
    return Scaffold(
      body: SafeArea(child: ConnectionWrapper(child: const InAppWebViewPage())),
    );
  }

  void _ensureDeviceId(BuildContext context) {
    final prov = context.read<SyncProvider>();
    if (prov.deviceId == null) {
      DeviceUtils.getDeviceId().then((id) => prov.setDeviceId(id));
    }
  }
}
