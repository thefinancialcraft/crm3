import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../services/permission_service.dart';
import '../services/call_log_service.dart';
import '../services/sync_service.dart';
import '../services/storage_service.dart';
import '../services/consent_service.dart';
import '../services/background_service.dart';
import '../utils/device_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants.dart';
import '../providers/sync_provider.dart';
import '../services/logger_service.dart';
import '../services/webbridge_service.dart';

import 'package:permission_handler/permission_handler.dart';

class InAppWebViewPage extends StatefulWidget {
  const InAppWebViewPage({super.key});

  @override
  State<InAppWebViewPage> createState() => _InAppWebViewPageState();
}

class _InAppWebViewPageState extends State<InAppWebViewPage> {
  bool _hasShownConsent = false;

  Future<void> _handleConsent() async {
    if (!mounted) return;

    // Show consent dialog
    bool isChecked = false;
    final accepted = await showDialog<bool>(
      context: Navigator.of(context, rootNavigator: true).context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          titlePadding: const EdgeInsets.all(16),
          contentPadding: const EdgeInsets.all(16),
          title: Column(
            children: [
              const Text(
                'Welcome to TFC Nexus',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(height: 2, color: Colors.blue.shade100),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'About TFC Nexus',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'TFC Nexus is your comprehensive CRM solution designed to streamline customer interactions and improve business relationships. This app helps you manage customer data efficiently and track all communication effectively.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'App Features & Permissions',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• Automatic Call Logging: Captures call details for better customer tracking',
                ),
                const Text(
                  '• Background Service: Ensures continuous call monitoring',
                ),
                const Text(
                  '• Cloud Sync: Securely uploads data to TFC CRM system',
                ),
                const Text('• Real-time Updates: Keeps your CRM data current'),
                const SizedBox(height: 16),
                const Text(
                  'Data Usage & Privacy',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'We value your privacy and handle your data with utmost care. The collected information is used exclusively for:',
                ),
                const SizedBox(height: 8),
                const Text('• Managing customer relationships'),
                const Text('• Improving service quality'),
                const Text('• Analyzing communication patterns'),
                const Text('• Generating business insights'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: isChecked,
                        onChanged: (bool? value) {
                          setState(() {
                            isChecked = value ?? false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'I have read and accept the terms. I allow TFC Nexus to collect and process my data as described above.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              style: TextButton.styleFrom(foregroundColor: Colors.grey),
              child: const Text('Decline'),
            ),
            TextButton(
              onPressed: isChecked
                  ? () => Navigator.of(dialogCtx).pop(true)
                  : null,
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue,
                backgroundColor: isChecked
                    ? Colors.blue.shade50
                    : Colors.grey.shade100,
              ),
              child: const Text('Accept'),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;

    if (accepted == true) {
      await ConsentService.markConsentAccepted();

      // Request permissions securely
      // await Future.delayed(const Duration(milliseconds: 500));
      await _ensurePermissions();

      // Initialize Background Service
      if (!kIsWeb) {
        await BackgroundService.setup();
      }

      // Initialize Call State Listener
      _startCallStateListener();

      // Initialize services only after permissions are granted
      await Future.delayed(const Duration(milliseconds: 500));
      final callSvc = CallLogService();
      final newCount = await callSvc.scanAndEnqueueNewCalls();
      final svc = SyncService(
        Supabase.instance.client,
        onProgress: (pending, synced) {
          if (!mounted) return;
          final prov = context.read<SyncProvider>();
          prov.setCounts(pending: pending, synced: synced);
        },
      );

      if (newCount > 0) await svc.syncPending();

      if (!mounted) return;

      // Update provider counts
      final pending = StorageService.callBucket.length;
      final synced = StorageService.syncedBucket.length;
      final deviceId = await DeviceUtils.getDeviceId();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final prov = context.read<SyncProvider>();
        prov.setCounts(pending: pending, synced: synced);
        prov.setLastSync(DateTime.now());
        prov.setDeviceId(deviceId);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // We'll check consent status in onLoadStop
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.read<SyncProvider>();
    return Scaffold(
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(AppConstants.defaultCrmUrl),
            ),
            initialSettings: InAppWebViewSettings(
              isInspectable: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              // Reduce graphics resource usage
              transparentBackground: true,
              disableVerticalScroll: false,
              disableHorizontalScroll: false,
            ),
            onWebViewCreated: (c) {
              LoggerService.ui('WebView created');
              WebBridgeService.init(c);
            },
            onLoadStart: (c, uri) {
              LoggerService.ui('WebView load start: ${uri?.toString() ?? ''}');
            },
            onLoadStop: (controller, uri) async {
              LoggerService.ui('WebView load stop: ${uri?.toString() ?? ''}');
              sync.addLog(LogCategory.ui, 'Web app loaded');

              if (!mounted) return;

              try {
                // Check if consent was already given
                if (!_hasShownConsent) {
                  _hasShownConsent = true; // Prevent showing multiple times
                  final hasConsent =
                      await ConsentService.hasUserAcceptedConsent();

                  if (!hasConsent) {
                    await _handleConsent();
                  } else {
                    // If consent was already given, check permissions and request if needed
                    await _ensurePermissions();

                    // Initialize Background Service
                    if (!kIsWeb) {
                      await BackgroundService.setup();
                    }

                    // Initialize Call State Listener
                    _startCallStateListener();

                    // Initialize services only after ensuring permissions
                    await Future.delayed(const Duration(milliseconds: 500));
                    final callSvc = CallLogService();
                    await callSvc.scanAndEnqueueNewCalls();
                    LoggerService.info(
                      'Initial scan complete, starting sync heartbeat...',
                    );
                    final svc = SyncService(
                      Supabase.instance.client,
                      onProgress: (pending, synced) {
                        if (!mounted) return;
                        final prov = context.read<SyncProvider>();
                        prov.setCounts(pending: pending, synced: synced);
                      },
                    );

                    await svc
                        .syncPending(); // This now updates meta even if 0 new calls

                    if (!mounted) return;

                    final pending = StorageService.callBucket.length;
                    final synced = StorageService.syncedBucket.length;
                    final deviceId = await DeviceUtils.getDeviceId();

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      final prov = context.read<SyncProvider>();
                      prov.setCounts(pending: pending, synced: synced);
                      prov.setLastSync(DateTime.now());
                      prov.setDeviceId(deviceId);
                    });
                  }
                }
              } catch (e) {
                LoggerService.warn('Consent/permission flow failed: $e');
              }
            },
          ),
          // Overlay removed from here to ensure only system-wide overlay is used.
        ],
      ),
    );
  }

  Future<void> _ensurePermissions() async {
    while (true) {
      if (!mounted) return;

      // 1. Request permissions first
      await PermissionService.requestEssential();

      // 2. Check if any are still missing
      final missing = await PermissionService.checkMissingPermissions();
      if (missing.isEmpty) {
        // All good!
        break;
      }

      if (!mounted) return;

      // 3. Show blocking dialog to retry
      await showDialog(
        context: Navigator.of(context, rootNavigator: true).context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Permissions Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The following permissions are required for the app to function:',
              ),
              const SizedBox(height: 12),
              ...missing.map(
                (p) => ListTile(
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: Text(p),
                  dense: true,
                ),
              ),
              const SizedBox(height: 12),
              const Text('Please tap the button below to grant them.'),
              const SizedBox(height: 8),
              if (missing.contains('Display Over Apps'))
                const Text(
                  'Make sure to enable "Display over other apps" for TFC CRM.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop(); // Close dialog first to avoid blocking

                if (missing.contains('Display Over Apps')) {
                  // Direct to special app access screen for overlay
                  await Permission.systemAlertWindow.request();
                } else {
                  // Direct to standard app settings
                  await openAppSettings();
                }
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
    }
  }

  void _startCallStateListener() {
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Initialize real-time call state listener (like Truecaller)
        CallLogService().initializeCallStateListener();
        LoggerService.info('Call state listener initialized');
      });
    } catch (_) {}
  }
}
