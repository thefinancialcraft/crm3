import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/sync_provider.dart';
import 'utils/device_utils.dart';
import 'services/notification_service.dart';
import 'services/call_log_service.dart';
import 'services/consent_service.dart';
import 'pages/inapp_webview_page.dart';
import 'pages/consent_page.dart';
import 'widgets/connection_wrapper.dart';
import 'services/logger_service.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  bool _isLoading = true;
  bool _hasFinishedOnboarding = false;

  @override
  void initState() {
    super.initState();
    _checkOnboardingState();
  }

  Future<void> _checkOnboardingState() async {
    debugPrint("🚀 App: Starting onboarding check...");
    // 🛡️ Failsafe: Don't stay stuck on splash forever
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _isLoading) {
        debugPrint("🚀 App: Failsafe triggered!");
        LoggerService.warn('Startup failsafe triggered: Proceeding despite incomplete init');
        setState(() => _isLoading = false);
      }
    });

    try {
      debugPrint("🚀 App: Checking ConsentService...");
      final bool hasFinished = await ConsentService.hasFinishedOnboarding().timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
      
      debugPrint("🚀 App: Onboarding finished = $hasFinished");
      if (hasFinished) {
        debugPrint("🚀 App: Initializing services...");
        // Initialize services with a timeout to prevent blocking the UI
        await _initializeServices().timeout(
          const Duration(seconds: 7),
          onTimeout: () => debugPrint('🚀 App: Service init timed out'),
        );
      }
      
      if (mounted) {
        debugPrint("🚀 App: Setting loading false");
        setState(() {
          _hasFinishedOnboarding = hasFinished;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("🚀 App: Error in startup: $e");
      LoggerService.error('Startup check failed', e);
      if (mounted) setState(() => _isLoading = false);
    }
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
    // We no longer return a MaterialApp here because it's already provided in main.dart
    return _buildHome();
  }

  Widget _buildHome() {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF4B33E8),
          ),
        ),
      );
    }

    // Defer the device ID setup to after the build phase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureDeviceId(context);
    });

    if (!_hasFinishedOnboarding) {
      return const ConsentPage();
    }

    // Show InAppWebViewPage wrapped with ConnectionWrapper to handle offline state
    return Material(
      color: Colors.white,
      child: ConnectionWrapper(child: const InAppWebViewPage()),
    );
  }

  void _ensureDeviceId(BuildContext context) {
    final prov = context.read<SyncProvider>();
    if (prov.deviceId == null) {
      DeviceUtils.getDeviceId().then((id) => prov.setDeviceId(id));
    }
  }
}
