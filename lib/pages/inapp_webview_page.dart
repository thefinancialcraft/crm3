import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../services/permission_service.dart';
import '../services/call_log_service_v2.dart';
import '../services/sync_service_v2.dart';
import '../services/storage_service.dart';
import '../services/consent_service.dart';
import '../utils/device_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants.dart';
import '../providers/sync_provider.dart';
import '../services/logger_service.dart';
import 'dev_mode_page.dart';

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
              Container(
                height: 2,
                color: Colors.blue.shade100,
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'About TFC Nexus',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
                const SizedBox(height: 8),
                const Text(
                  'TFC Nexus is your comprehensive CRM solution designed to streamline customer interactions and improve business relationships. This app helps you manage customer data efficiently and track all communication effectively.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'App Features & Permissions',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
                const SizedBox(height: 8),
                const Text('• Automatic Call Logging: Captures call details for better customer tracking'),
                const Text('• Background Service: Ensures continuous call monitoring'),
                const Text('• Cloud Sync: Securely uploads data to TFC CRM system'),
                const Text('• Real-time Updates: Keeps your CRM data current'),
                const SizedBox(height: 16),
                const Text(
                  'Data Usage & Privacy',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
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
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey,
              ),
              child: const Text('Decline'),
            ),
            TextButton(
              onPressed: isChecked 
                ? () => Navigator.of(dialogCtx).pop(true)
                : null,
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue,
                backgroundColor: isChecked ? Colors.blue.shade50 : Colors.grey.shade100,
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
      
      // Request permissions one by one with slight delay
      await Future.delayed(const Duration(milliseconds: 500));
      await PermissionService.requestEssential();
      
      // Initialize services only after permissions are granted
      await Future.delayed(const Duration(milliseconds: 500));
      final callSvc = CallLogService();
      final newCount = await callSvc.scanAndEnqueueNewCalls();
      final svc = SyncService(Supabase.instance.client, onProgress: (pending, synced) {
        if (!mounted) return;
        final prov = context.read<SyncProvider>();
        prov.setCounts(pending: pending, synced: synced);
      });

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
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(30),
        child: GestureDetector(
          onDoubleTap: () {
            LoggerService.ui('Header double tapped - opening Dev Mode');
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DevModePage()),
            );
          },
          child: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            title: const Text(
              'TFC Nexus',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            centerTitle: true,
            automaticallyImplyLeading: false, // Removes back button
            // Removed the dev mode icon since we now use double tap
          ),
        ),
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(AppConstants.defaultCrmUrl)),
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
              final hasConsent = await ConsentService.hasUserAcceptedConsent();
              
              if (!hasConsent) {
                await _handleConsent();
              } else {
                // If consent was already given, check permissions and request if needed
                await Future.delayed(const Duration(milliseconds: 500));
                await PermissionService.requestEssential();
                
                // Initialize services only after ensuring permissions
                await Future.delayed(const Duration(milliseconds: 500));
                final callSvc = CallLogService();
                final newCount = await callSvc.scanAndEnqueueNewCalls();
                final svc = SyncService(Supabase.instance.client, onProgress: (pending, synced) {
                  if (!mounted) return;
                  final prov = context.read<SyncProvider>();
                  prov.setCounts(pending: pending, synced: synced);
                });

                if (newCount > 0) await svc.syncPending();

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
    );
  }
}