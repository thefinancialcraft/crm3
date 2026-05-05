import 'package:flutter/material.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../services/call_log_service.dart';
import '../services/sync_service.dart';
import '../services/storage_service.dart';
import '../services/background_service.dart';
import '../utils/device_utils.dart';
import '../constants.dart';
import '../providers/sync_provider.dart';
import '../services/logger_service.dart';
import '../services/webbridge_service.dart';
import '../utils/log_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';

class InAppWebViewPage extends StatefulWidget {
  const InAppWebViewPage({super.key});

  @override
  State<InAppWebViewPage> createState() => _InAppWebViewPageState();
}

class _InAppWebViewPageState extends State<InAppWebViewPage> {
  bool _hasInitializedServices = false;

  @override
  void initState() {
    super.initState();
    // 🚀 AUTOMATIC UPDATE CHECK (15s Delay)
    // Runs once when the WebView page is first created
    LoggerService.info("🚀 Auto-update check scheduled in 15 seconds...");
    Future.delayed(const Duration(seconds: 15), () {
      final globalContext = LoggerService.navKey.currentContext;
      if (globalContext != null && globalContext.mounted) {
        LoggerService.info("🚀 Executing automatic update check (Global Context)...");
        UpdateService.instance.checkForUpdate(globalContext, silent: true);
      } else {
        LoggerService.warn("🚀 Auto-update skipped: Global context not available");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.read<SyncProvider>();
    return Scaffold(
        body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(AppConstants.defaultCrmUrl),
              ),
              gestureRecognizers: {
                Factory<VerticalDragGestureRecognizer>(() => VerticalDragGestureRecognizer()),
                Factory<HorizontalDragGestureRecognizer>(() => HorizontalDragGestureRecognizer()),
                Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
                Factory<LongPressGestureRecognizer>(() => LongPressGestureRecognizer()),
              },
              initialSettings: InAppWebViewSettings(
                isInspectable: true,
                javaScriptEnabled: true,
                domStorageEnabled: true,
                databaseEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                transparentBackground: false,
                disableVerticalScroll: false,
                disableHorizontalScroll: false,
                supportZoom: true,
                builtInZoomControls: true,
                displayZoomControls: false,
              ),
              onWebViewCreated: (c) {
                LoggerService.ui('WebView created');
                WebBridgeService.init(c);
              },
              onLoadStart: (c, uri) {
                LoggerService.ui('WebView load start: ${uri?.toString() ?? ''}');
                // If it's a deep link (whatsapp/mailto outside http/https), let the device handle it
                if (uri != null &&
                    ![
                      "http",
                      "https",
                      "file",
                      "chrome",
                      "data",
                      "javascript",
                      "about",
                    ].contains(uri.scheme)) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                  c.stopLoading();
                }
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                var uri = navigationAction.request.url;
                if (uri == null) return NavigationActionPolicy.ALLOW;
  
                bool isWhatsApp =
                    uri.scheme == 'whatsapp' ||
                    uri.host == 'wa.me' ||
                    uri.host == 'api.whatsapp.com';
  
                if (isWhatsApp) {
                  try {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } catch (e) {
                    LoggerService.error("Failed to force launch WhatsApp", e);
                  }
                  return NavigationActionPolicy.CANCEL;
                }
  
                if (![
                  "http",
                  "https",
                  "file",
                  "chrome",
                  "data",
                  "javascript",
                  "about",
                ].contains(uri.scheme)) {
                  try {
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } else {
                      LoggerService.warn("Could not launch external link: $uri");
                    }
                  } catch (e) {
                    LoggerService.error("Failed to launch URL: $uri", e);
                  }
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
              onLoadStop: (controller, uri) async {
                LoggerService.ui('WebView load stop: ${uri?.toString() ?? ''}');
                sync.addLog(LogCategory.ui, 'Web app loaded');
  
                if (!mounted) return;
  
                try {
                  if (!_hasInitializedServices) {
                    _hasInitializedServices = true;
  
                    // Initialize Background Service
                    if (!kIsWeb) {
                      await BackgroundService.setup();
                    }
  
                    // Initialize services
                    await Future.delayed(const Duration(milliseconds: 500));
                    final callSvc = CallLogService();
                    await callSvc.initializeCallStateListener();
                    
                    LoggerService.info('Starting UI sync heartbeat...');
                    
                    final svc = SyncService.instance;
                    svc.onProgress = (pending, synced) {
                      if (!mounted) return;
                      final prov = context.read<SyncProvider>();
                      prov.setCounts(pending: pending, synced: synced);
                    };
  
                    svc.syncPending().then((_) {
                      if (!mounted) return;
                      LoggerService.info('Initial UI syncPending complete');
                    });
  
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
                    // Heartbeat logic or other services can go here
                  }
                } catch (e) {
                  LoggerService.warn('Initialization flow failed: $e');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
