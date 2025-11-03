import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'constants.md';
import 'call_log_service.dart';

// A global key so we can show SnackBars without needing a BuildContext
// across async gaps. This avoids use_build_context_synchronously lints.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background service
  try {
    await CallLogService.initializeBackgroundService();
    debugPrint('Background service initialized successfully');
  } catch (e) {
    debugPrint('Error initializing background service: $e');
  }

  // Initialize Supabase
  debugPrint(
    'Initializing Supabase with URL: ${SupabaseConstants.supabaseUrl}',
  );
  await Supabase.initialize(
    url: SupabaseConstants.supabaseUrl,
    anonKey: SupabaseConstants.supabaseAnonKey,
  );

  // Check if Supabase is properly initialized
  try {
    Supabase.instance.client;
    debugPrint('Supabase client initialized successfully');
  } catch (e) {
    debugPrint('Error initializing Supabase client: $e');
  }

  // Wait until after widget tree is built to request permissions
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (Platform.isAndroid) {
      final callLogService = CallLogService();
      final hasPermission = await callLogService.requestPermission();
      debugPrint('Call log permission status: $hasPermission');
    }
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '',
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: ThemeData(useMaterial3: true),
      home: const BlankScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class BlankScreen extends StatefulWidget {
  const BlankScreen({super.key});

  @override
  State<BlankScreen> createState() => _BlankScreenState();
}

class _BlankScreenState extends State<BlankScreen> {
  late CallLogService _callLogService;
  final List<String> _logMessages = [];
  bool _isProcessing = false;
  int _fetchedCount = 0;
  int _syncedCount = 0;
  final ScrollController _scrollController = ScrollController();

  // Call log stats
  int _totalLogs = 0;
  int _missedCalls = 0;
  DateTime? _latestCallTime;
  DateTime? _lastSyncTime;

  // State to control visibility - show WebView by default
  bool _showSupabaseSetup = false;

  // WebView state
  bool _webViewLoading = false;
  String _webViewError = '';
  InAppWebViewController? _webViewController;
  Timer? _readyCheckTimer;
  // Track whether the WebView can go back in its history. Kept in state so
  // `PopScope.canPop` can synchronously decide whether to allow system pops.
  bool _webViewCanGoBack = false;

  Future<void> _updateStats() async {
    final stats = await _callLogService.getCallLogStats();
    final syncTime = _callLogService.getLastSyncTime();

    setState(() {
      _totalLogs = stats['total'] as int;
      _missedCalls = stats['missed'] as int;
      _latestCallTime = stats['latest'] as DateTime?;
      _lastSyncTime = syncTime;
    });
  }

  @override
  void initState() {
    super.initState();
    _callLogService = CallLogService();
    _addLogMessage('App initialized. Ready to fetch and sync call logs.');

    // Test Supabase connection and update stats
    _testSupabaseConnection();
    _updateStats();

    // Start automatic in-app sync (runs while app is active)
    try {
      _callLogService.startAutoSync(() async {
        // Update stats whenever sync happens (auto or manual)
        await _updateStats();
        setState(() {}); // Trigger UI update
      });
      _addLogMessage('Auto-sync started (in-app).');
    } catch (e) {
      _addErrorMessage('Failed to start auto-sync: $e');
    }
  }

  void _testSupabaseConnection() async {
    try {
      final supabase = Supabase.instance.client;
      // Try a simple query to test the connection
      final response = await supabase.from('call_logs').select().limit(1);
      _addLogMessage('Supabase connection test successful.');
      debugPrint('Supabase connection test response: $response');
    } catch (e) {
      _addErrorMessage('Supabase connection test failed: $e');
    }
  }

  void _addLogMessage(String message) {
    setState(() {
      _logMessages.insert(
        0,
        '[${DateTime.now().toString().split('.').first}] $message',
      );
    });
    // Auto-scroll to bottom when new messages are added
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
    debugPrint(message);
  }

  void _addErrorMessage(String message) {
    setState(() {
      _logMessages.insert(
        0,
        '[${DateTime.now().toString().split('.').first}] ERROR: $message',
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
    debugPrint('ERROR: $message');
  }

  void _copyLogsToClipboard() {
    final String allLogs = _logMessages.reversed.join('\n');
    Clipboard.setData(ClipboardData(text: allLogs));
    // Use the global scaffold messenger key to avoid using a BuildContext
    // across async gaps.
    scaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Text('Logs copied to clipboard'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _handleStartButtonPressed() async {
    // Check if platform is iOS
      if (Theme.of(context).platform == TargetPlatform.iOS) {
      _addErrorMessage('Call logs are not supported on iOS');
      // Show message that call logs are not supported on iOS
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Call logs are not supported on iOS'),
            backgroundColor: Colors.red,
          ),
        );
      return;
    }

    // For Android, read and upload logs
    await _readAndUploadLogs();
  }

  Future<void> _sendFakeData() async {
    setState(() {
      _isProcessing = true;
    });

    _addLogMessage('Sending fake test data to Supabase...');

    try {
      final success = await _callLogService.sendFakeData();

        if (success) {
        _addLogMessage('Successfully sent fake test data to Supabase.');
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Fake data sent successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        _addErrorMessage(
          'Failed to send fake test data to Supabase. Check the logs for more details.',
        );
      }
    } catch (e, stackTrace) {
      _addErrorMessage('Error sending fake data: $e');
      _addErrorMessage('Stack trace: $stackTrace');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _readAndUploadLogs() async {
    setState(() {
      _isProcessing = true;
      _fetchedCount = 0;
      _syncedCount = 0;
    });

    _addLogMessage('Starting call log fetch and sync process...');

    try {
      // Request permission
      _addLogMessage('Requesting permission to read call logs...');
      final hasPermission = await _callLogService.requestPermission();

        if (!hasPermission) {
        _addErrorMessage(
          'Permission denied. Cannot read call logs. Please grant permission in settings.',
        );
        // Show snackbar when permission is denied
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Permission required to read call logs'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      _addLogMessage('Permission granted. Reading call logs...');

      // Read call logs
      final callLogs = await _callLogService.readCallLogs();

      if (callLogs == null) {
        _addErrorMessage(
          'Error reading call logs. Please check device permissions.',
        );
        return;
      }

      if (callLogs.isEmpty) {
        _addLogMessage('No call logs found on device.');
        return;
      }

      setState(() {
        _fetchedCount = callLogs.length;
      });

      _addLogMessage('Successfully fetched $_fetchedCount call logs.');

      // Upload only new call logs using sync metadata
      _addLogMessage('Uploading new call logs to Supabase...');

      // Set callback for sync
      _callLogService.onSyncComplete = () async {
        await _updateStats();
        setState(() {}); // Trigger UI update
      };

      final uploadedCount = await _callLogService.uploadNewCallLogs();

      if (uploadedCount >= 0) {
        setState(() {
          _syncedCount = uploadedCount;
        });
        _addLogMessage(
          'Successfully uploaded $uploadedCount new call logs to Supabase.',
        );
      } else {
        _addErrorMessage(
          'Failed to sync call logs to Supabase. Please check your internet connection and Supabase configuration.',
        );
      }
    } catch (e, stackTrace) {
      _addErrorMessage('Unexpected error during process: $e');
      _addErrorMessage('Stack trace: $stackTrace');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // Note: back button handling is implemented via `PopScope` in `build`.





  @override
  Widget build(BuildContext context) {
    // Note: WillPopScope is deprecated in newer Flutter versions; replace
    // with `PopScope` when targeting Flutter >= 3.12 and after verifying the
    // correct `PopScope` callback signature in your SDK. For now we retain
    // `WillPopScope` to ensure compatibility and a successful build.
    // Use PopScope to replace the deprecated WillPopScope. We compute
    // `canPop` synchronously using `_webViewCanGoBack` and `_showSupabaseSetup`.
    // When `canPop` is false, system back gestures are blocked and
    // `onPopInvokedWithResult` is called with `didPop == false` where we can
    // show a confirmation dialog and perform a programmatic pop if confirmed.
    return PopScope<dynamic>(
      canPop: !(!_showSupabaseSetup && !_webViewCanGoBack),
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        // If the pop actually happened, there's nothing to do.
        if (didPop) return;

        // Guard if widget disposed while handling pop invocation.
        if (!mounted) return;

        // If in Supabase setup view, just go back to the WebView (same as
        // previous behavior) and don't exit the app.
        if (_showSupabaseSetup) {
          setState(() {
            _showSupabaseSetup = false;
          });
          return;
        }

        // If the WebView can go back in history, navigate back instead of
        // exiting the app.
        if (!_showSupabaseSetup && _webViewController != null && _webViewCanGoBack) {
          try {
            _webViewController!.goBack();
          } catch (e) {
            debugPrint('[WebView] goBack error: $e');
          }
          return;
        }

        // Otherwise show the exit confirmation dialog like before.
        // Capture the NavigatorState before awaiting so we don't need to use
        // a BuildContext after the async gap.
        final navigator = Navigator.of(context);
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Exit App?'),
            content: const Text('Are you sure you want to exit the app?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Yes'),
              ),
            ],
          ),
        );

        if (shouldExit == true) {
          // Programmatically pop the route using the captured Navigator.
          navigator.maybePop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            // Top bar with three dots
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                color: Colors.blue,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // small left padding to align title visually
                  const SizedBox(width: 8),
                  // title centered but constrained so it doesn't push content
                  const Expanded(
                    child: Text(
                      '',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16, // smaller font so it doesn't impact view
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  // three horizontal dots on the right
                  IconButton(
                    icon: const Icon(Icons.more_horiz, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _showSupabaseSetup = !_showSupabaseSetup;
                      });
                    },
                    tooltip: 'Menu',
                  ),
                ],
              ),
            ),

            // Content area - either Supabase Setup or WebView
            Expanded(
              child:
                  _showSupabaseSetup
                      ? Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Status display
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isProcessing ? 'Processing...' : 'Ready',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Fetched: $_fetchedCount | Synced: $_syncedCount',
                                  ),
                                  const Divider(),
                                  Text(
                                    'Total Logs: $_totalLogs | Missed Calls: $_missedCalls',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  if (_latestCallTime != null)
                                    Text(
                                      'Latest Call: ${_latestCallTime!.toLocal().toString().split('.')[0]}',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  if (_lastSyncTime != null)
                                    Text(
                                      'Last Sync: ${_lastSyncTime!.toLocal().toString().split('.')[0]}',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Action buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton(
                                  onPressed:
                                      _isProcessing
                                          ? null
                                          : _handleStartButtonPressed,
                                  child:
                                      _isProcessing
                                          ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                          : const Text('Start'),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton(
                                  onPressed:
                                      _isProcessing ? null : _sendFakeData,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                  ),
                                  child: const Text('Send Fake Data'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            // Console log display with copy button
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    // Header with copy button
                                    Container(
                                      height: 40,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      decoration: const BoxDecoration(
                                        color: Colors.grey,
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(8),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Console Log',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.copy,
                                              color: Colors.white,
                                            ),
                                            onPressed: _copyLogsToClipboard,
                                            tooltip: 'Copy logs to clipboard',
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Log messages
                                    Expanded(
                                      child: ListView.builder(
                                        controller: _scrollController,
                                        reverse: true,
                                        itemCount: _logMessages.length,
                                        itemBuilder: (context, index) {
                                          final message = _logMessages[index];
                                          final isErrorMessage = message
                                              .contains('ERROR:');
                                          return Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Text(
                                              message,
                                              style: TextStyle(
                                                color:
                                                    isErrorMessage
                                                        ? Colors.red
                                                        : Colors.green,
                                                fontFamily: 'monospace',
                                                fontSize: 12,
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
                          ],
                        ),
                      )
                      : Stack(
                        children: [
                          InAppWebView(
                            initialUrlRequest: URLRequest(
                              url: WebUri(
                                'https://thefinancialcraft.github.io/dumCrm/#',
                              ),
                            ),
                            initialSettings: InAppWebViewSettings(
                              useHybridComposition: true,
                              allowUniversalAccessFromFileURLs: true,
                              javaScriptEnabled: true,
                              useShouldOverrideUrlLoading: true,
                              mediaPlaybackRequiresUserGesture: false,
                            ),
                            onWebViewCreated: (controller) {
                              _webViewController = controller;
                              debugPrint('[WebView] onWebViewCreated');

                              // Add JavaScript handler for phone calls
                              controller.addJavaScriptHandler(
                                handlerName: 'makePhoneCall',
                                callback: (args) async {
                                  if (args.isNotEmpty) {
                                    final phoneNumber = args[0].toString();
                                    try {
                                      final uri = Uri(
                                        scheme: 'tel',
                                        path: phoneNumber,
                                      );
                                      await launchUrl(
                                        uri,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    } catch (e) {
                                      debugPrint(
                                        'Error launching phone call: $e',
                                      );
                                    }
                                  }
                                },
                              );
                            },
                            shouldOverrideUrlLoading: (
                              controller,
                              navigationAction,
                            ) async {
                              final uri = navigationAction.request.url!;
                              debugPrint(
                                '[WebView] shouldOverrideUrlLoading url=$uri',
                              );

                              if (uri.scheme == 'tel') {
                                try {
                                  // Extract phone number and clean it
                                  final phoneNumber = uri.path.replaceAll(
                                    RegExp(r'[^\d+]'),
                                    '',
                                  );

                                  // Check if we have permission to make phone calls
                                  final status = await Permission.phone.status;
                                  if (!status.isGranted) {
                                    final result =
                                        await Permission.phone.request();
                                    if (!result.isGranted) {
                                      throw 'Phone permission denied';
                                    }
                                  }

                                  // Auto-launch dialer with the number
                                  final canLaunch = await canLaunchUrl(uri);
                                  if (!canLaunch) {
                                    throw 'Could not launch dialer';
                                  }

                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                  if (!mounted) return NavigationActionPolicy.CANCEL;
                                  scaffoldMessengerKey.currentState?.showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(
                                            Icons.phone,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 8),
                                          Text('Calling $phoneNumber...'),
                                        ],
                                      ),
                                      duration: const Duration(seconds: 2),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                  return NavigationActionPolicy.CANCEL;
                                } catch (e) {
                                  debugPrint(
                                    '[WebView] Error launching dialer: $e',
                                  );
                                  if (!mounted) return NavigationActionPolicy.ALLOW;
                                  scaffoldMessengerKey.currentState?.showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(
                                            Icons.error,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Could not initiate call: ${e.toString()}',
                                            ),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: Colors.red,
                                      duration: const Duration(seconds: 4),
                                      action: SnackBarAction(
                                        label: 'Settings',
                                        onPressed: () {
                                          openAppSettings();
                                        },
                                        textColor: Colors.white,
                                      ),
                                    ),
                                  );
                                  return NavigationActionPolicy.ALLOW;
                                }
                              } else if (uri.scheme == 'whatsapp') {
                                try {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                  return NavigationActionPolicy.CANCEL;
                                } catch (e) {
                                  debugPrint(
                                    '[WebView] Error launching WhatsApp: $e',
                                  );
                                  if (!mounted) return NavigationActionPolicy.ALLOW;
                                  scaffoldMessengerKey.currentState?.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not open WhatsApp',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return NavigationActionPolicy.ALLOW;
                                }
                              }
                              return NavigationActionPolicy.ALLOW;
                            },
                            onLoadStart: (controller, url) {
                              // page started loading - show spinner
                              debugPrint('[WebView] onLoadStart url=$url');
                              if (mounted) {
                                setState(() {
                                  _webViewLoading = true;
                                  _webViewError = '';
                                });
                              }
                              // start a periodic JS-ready check as a fallback for SPA pages
                              _readyCheckTimer?.cancel();
                              _readyCheckTimer = Timer.periodic(
                                const Duration(milliseconds: 500),
                                (timer) async {
                                  try {
                                    final result = await controller
                                        .evaluateJavascript(
                                          source: 'document.readyState',
                                        );
                                    debugPrint(
                                      '[WebView] document.readyState -> $result',
                                    );
                                    if (result != null) {
                                      final ready =
                                          result.toString().toLowerCase();
                                      if (ready.contains('complete')) {
                                        if (mounted) {
                                          setState(() {
                                            _webViewLoading = false;
                                          });
                                        }
                                        timer.cancel();
                                      }
                                    }
                                  } catch (e) {
                                    // ignore evaluation errors until page is ready
                                  }
                                },
                              );
                            },
                            onLoadStop: (controller, url) {
                              // page finished loading according to WebView
                              debugPrint('[WebView] onLoadStop url=$url');
                              if (mounted) {
                                setState(() {
                                  _webViewLoading = false;
                                });
                              }
                              // Update whether the webview can go back so we can
                              // synchronously decide about system pop handling.
                              () async {
                                try {
                                  final canGoBack = await controller.canGoBack();
                                  if (mounted) {
                                    setState(() {
                                      _webViewCanGoBack = canGoBack;
                                    });
                                  }
                                } catch (e) {
                                  // ignore
                                }
                              }();
                              // cancel JS-ready fallback
                              _readyCheckTimer?.cancel();
                              _readyCheckTimer = null;
                            },
                            onReceivedError: (controller, request, error) {
                              // loading failed
                              debugPrint(
                                '[WebView] onReceivedError url=${request.url} type=${error.type} description=${error.description}',
                              );
                              if (mounted) {
                                setState(() {
                                  _webViewLoading = false;
                                  _webViewError =
                                      '${error.type}: ${error.description}';
                                });
                              }
                              _readyCheckTimer?.cancel();
                              _readyCheckTimer = null;
                            },
                            onProgressChanged: (controller, progress) {
                              debugPrint(
                                '[WebView] onProgressChanged progress=$progress',
                              );
                              // Some sites (SPA) never fire loadStop; use progress==100 as a fallback
                              if (progress == 100) {
                                if (mounted) {
                                  setState(() {
                                    _webViewLoading = false;
                                  });
                                  _readyCheckTimer?.cancel();
                                  _readyCheckTimer = null;
                                }
                              }
                            },
                            onConsoleMessage: (controller, consoleMessage) {
                              debugPrint(
                                '[WebView][console] ${consoleMessage.message}',
                              );
                            },
                          ),
                          if (_webViewLoading)
                            const Center(child: CircularProgressIndicator()),
                          if (_webViewError.isNotEmpty)
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.error,
                                    size: 64,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Error: $_webViewError',
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 16,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () {
                                      _webViewController?.reload();
                                    },
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
            ),
          ],
        ),
      ),
    );
  } // close build method

  @override
  void dispose() {
    _scrollController.dispose();
    _readyCheckTimer?.cancel();
    _readyCheckTimer = null;
    super.dispose();
  }
} // close _BlankScreenState class
