import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/sync_service.dart';
import '../services/logger_service.dart';
import '../constants.dart';
import '../services/storage_service.dart';

@pragma("vm:entry-point")
Future<void> overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Hive.initFlutter();
    await StorageService.init();
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
  } catch (e) {
    LoggerService.error('[_from_overlay] Supabase init error', e);
  }
  runApp(
    Directionality(
      textDirection: ui.TextDirection.ltr,
      child: const Material(
        color: Colors.transparent,
        child: CallOverlayScreen(),
      ),
    ),
  );
}

class CallOverlayScreen extends StatelessWidget {
  const CallOverlayScreen({super.key});
  @override
  Widget build(BuildContext context) => const _CallOverlayScreenBody();
}

class _CallOverlayScreenBody extends StatefulWidget {
  const _CallOverlayScreenBody();
  @override
  State<_CallOverlayScreenBody> createState() => _CallOverlayScreenBodyState();
}

class _CallOverlayScreenBodyState extends State<_CallOverlayScreenBody> {
  final GlobalKey _columnKey = GlobalKey();
  final GlobalKey _bubbleKey = GlobalKey();
  final platform = const MethodChannel('com.example.crm3/overlay');
  final SyncService _syncSvc = SyncService.instance;

  String number = "Unknown";
  String? nativeNo;
  String name = "";  
  String? contactNameFromPhone; // 🚀 New: Store name from native phonebook
  String status = "Unknown";
  String? expiryDate;
  Map<String, dynamic> customerDetails = {};
  bool isPersonal = false;
  bool _isLookupInProgress = false;
  bool _showFullCard = false;
  double _lastHeight = 0;

  void _updateUI(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    _safeUpdateHeight();
  }

  Widget _buildLoadingBubble() {
    return Container(
      key: _bubbleKey,
      padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search, size: 18, color: Color(0xFF3F51B5)),
          const SizedBox(width: 12),
          const _DancingDots(),
          const SizedBox(width: 16),
          // --- Close Button ---
          GestureDetector(
            onTap: () async {
              try {
                await platform.invokeMethod('closeOverlay');
              } catch (e) {
                debugPrint("Error closing overlay: $e");
              }
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _setupMethodChannel(); // 🚀 CRITICAL: Start listening to native messages
    
    // 🛡️ INITIALIZATION DELAY: Give native bridge time to register
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _getInitialData();
    });
  }

  /// 🛡️ Robust wrapper for platform calls to handle race conditions during startup
  Future<T?> _invokeMethodWithRetry<T>(String method, [dynamic arguments, int retries = 3]) async {
    for (int i = 0; i < retries; i++) {
      try {
        return await platform.invokeMethod<T>(method, arguments);
      } on MissingPluginException {
        if (i == retries - 1) rethrow;
        await Future.delayed(Duration(milliseconds: 200 * (i + 1)));
      } catch (e) {
        rethrow;
      }
    }
    return null;
  }

  void _setupMethodChannel() {
    platform.setMethodCallHandler((call) async {
      debugPrint("[OverlayChannel] Method called: ${call.method}");
      if (call.method == "clearData") {
        _updateUI(() {
          number = "Unknown";
          name = "";
          contactNameFromPhone = null;
          status = "Connecting...";
          isPersonal = true;
          expiryDate = null;
          customerDetails = {};
          _isLookupInProgress = false;
          _showFullCard = false; 
        });
      }
      if (call.method == "updateData" || call.method == "updateLookupResult") {
        final args = call.arguments;
        debugPrint("[OverlayChannel] Arguments: $args");
        if (args is Map && mounted) {
          final String incomingNo = args['number']?.toString() ?? number;
          
          final String cleanNew = incomingNo.replaceAll(RegExp(r'[^0-9]'), '').split('').reversed.take(10).toList().reversed.join();
          final String cleanOld = number.replaceAll(RegExp(r'[^0-9]'), '').split('').reversed.take(10).toList().reversed.join();

          _updateUI(() {
            if (cleanNew != cleanOld && cleanNew.isNotEmpty) {
              debugPrint("[OverlayChannel] New number detected: $incomingNo");
              name = "";
              contactNameFromPhone = args['contactName']?.toString();
              isPersonal = true;
              expiryDate = null;
              customerDetails = {};
              _isLookupInProgress = false;
              _showFullCard = false; 
              number = incomingNo;
              _performLocalLookup();
            } else {
              number = incomingNo;
              if (args['contactName'] != null) {
                 contactNameFromPhone = args['contactName'].toString();
              }
            }
            status = args['status'] ?? status;
            if (args['name'] != null && args['name'].toString().isNotEmpty && args['name'] != "Searching...") {
              debugPrint("[OverlayChannel] Data received from native: ${args['name']}");
              name = args['name'];
              isPersonal = args['isPersonal'] ?? false;
              expiryDate = args['expiry_date']?.toString();
              
              dynamic rawDetails = args['customer_details'];
              if (rawDetails is Map) {
                customerDetails = Map<String, dynamic>.from(rawDetails);
              }
              _showFullCard = true; 
            }
          });
          
          if (name.isEmpty && number != "Unknown" && number.isNotEmpty && !_isLookupInProgress) {
            _performLocalLookup();
          }
        }
      }
      return null;
    });
  }

  Future<void> _getInitialData() async {
    debugPrint("[OverlayInit] Getting initial data...");
    if (mounted) {
      _updateUI(() {
        number = "Unknown";
        name = "";
        contactNameFromPhone = null;
        status = "Connecting...";
        isPersonal = true;
        customerDetails = {};
        _isLookupInProgress = false;
        _showFullCard = false;
      });
    }
    try {
      final String? nativeNo = await _invokeMethodWithRetry<String>('getNativeNumber');
      final dynamic preData = await _invokeMethodWithRetry<dynamic>('getPreStartData');
      debugPrint("[OverlayInit] Native No: $nativeNo, PreData: ${preData != null ? 'Present' : 'Empty'}");
      
      if (mounted) {
        _updateUI(() {
          if (preData is Map) {
            number = preData['number'] ?? nativeNo ?? number;
            name = preData['name'] ?? "";
            contactNameFromPhone = preData['contactName']?.toString();
            status = preData['status'] ?? status;
            isPersonal = preData['isPersonal'] ?? isPersonal;
            expiryDate = preData['expiry_date'];
            if (preData['customer_details'] is Map) {
              customerDetails = Map<String, dynamic>.from(preData['customer_details']);
            }
            _showFullCard = true;
          }
        });
        if (name.isEmpty && number != "Unknown" && number.isNotEmpty) {
          _performLocalLookup();
        }
      }
    } catch (e) {
      debugPrint("[OverlayInit] Error: $e");
    }
  }

  void _safeUpdateHeight() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateHeight();
    });
  }

  void _updateHeight() async {
    try {
      final RenderBox? cardBox = _columnKey.currentContext?.findRenderObject() as RenderBox?;
      final RenderBox? bubbleBox = _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
      final RenderBox? renderBox = cardBox ?? bubbleBox;

      if (renderBox != null) {
        final double newHeight = renderBox.size.height;
        if (newHeight > 20 && (newHeight - _lastHeight).abs() > 3) {
          _lastHeight = newHeight;
          final pixelRatio = MediaQuery.of(context).devicePixelRatio;
          const double extraBuffer = 56.0;
          int pixelHeight = ((newHeight + extraBuffer) * pixelRatio).toInt();
          debugPrint("[OverlayHeight] Updating native height: $pixelHeight px");
          await _invokeMethodWithRetry('updateHeight', {'height': pixelHeight});
        }
      }
    } catch (e) {
      debugPrint("[OverlayHeight] Error: $e");
    }
  }

  Future<void> _performLocalLookup({int attempt = 1}) async {
    final String lookupNumber = number;
    debugPrint("[OverlayLookup] Starting lookup for: $lookupNumber (Attempt $attempt)");
    if (lookupNumber == "Unknown" || lookupNumber.isEmpty) return;

    if (_isLookupInProgress && attempt == 1) {
      debugPrint("[OverlayLookup] Lookup already in progress, skipping.");
      return;
    }
    _isLookupInProgress = true;

    try {
      String normalized = lookupNumber.replaceAll(RegExp(r'[^0-9]'), '');
      if (normalized.length > 10) {
        normalized = normalized.substring(normalized.length - 10);
      }
      
      debugPrint("[OverlayLookup] Calling SyncService for: $normalized");
      // 🕒 TIMEOUT PROTECTION
      final result = await _syncSvc.lookupCustomer(normalized).timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          debugPrint("[OverlayLookup] TIMEOUT reached for $normalized");
          return null;
        },
      );
      
      debugPrint("[OverlayLookup] Result received: ${result != null ? 'DATA FOUND' : 'NULL'}");
      
      if (!mounted || number != lookupNumber) {
        debugPrint("[OverlayLookup] Context unmounted or number changed, aborting UI update.");
        _isLookupInProgress = false;
        return;
      }

      if (result != null) {
        final String foundName = result['customer_name'] ?? "";
        debugPrint("[OverlayLookup] Success! Name: $foundName");
        _updateUI(() {
          name = foundName;
          isPersonal = false;
          status = result['status'] ?? "Unknown";
          expiryDate = result['expiry_date']?.toString();
          
          try {
            dynamic detailsRaw = result['customer_details'];
            if (detailsRaw is Map) {
              customerDetails = Map<String, dynamic>.from(detailsRaw);
            } else if (detailsRaw is String && detailsRaw.isNotEmpty) {
              customerDetails = Map<String, dynamic>.from(jsonDecode(detailsRaw));
            }
          } catch (e) {
            debugPrint("[OverlayLookup] Details parse error: $e");
          }

          _isLookupInProgress = false;
          _showFullCard = true; // 🚀 SHOW CARD
        });
      } else {
        debugPrint("[OverlayLookup] No data found in DB, switching to personal.");
        _updateUI(() {
          isPersonal = true;
          name = "";
          customerDetails = {};
          _isLookupInProgress = false;
          _showFullCard = true; // 🚀 SHOW PERSONAL CARD
        });
      }
    } catch (e) {
      debugPrint("[OverlayLookup] CRITICAL ERROR: $e");
      _updateUI(() {
        isPersonal = true;
        _isLookupInProgress = false;
        _showFullCard = true; 
      });
    }
  }

  String _cleanKey(String key) => key
      .replaceAll('_checked', '')
      .replaceAll('_unchecked', '')
      .replaceAll('_', ' ')
      .trim()
      .toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: !_showFullCard
              ? _buildLoadingBubble()
              : Container(
                  key: _columnKey,
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // --- Header Section ---
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: isPersonal
                                  ? [const Color(0xFF43A047), const Color(0xFF66BB6A)] // Green for Personal
                                  : [const Color(0xFF3F51B5), const Color(0xFF5C6BC0)], // Blue for Customer
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.person, color: Colors.white, size: 24),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isPersonal
                                          ? (contactNameFromPhone?.isNotEmpty == true 
                                              ? (contactNameFromPhone!.length > 15 
                                                  ? "${contactNameFromPhone!.substring(0, 15)}..." 
                                                  : contactNameFromPhone!)
                                              : "Unknown Contact")
                                          : (name.isEmpty
                                              ? "Unknown Caller"
                                              : (name.length > 15 ? "${name.substring(0, 15)}..." : name)),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      number,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isPersonal)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildBadge(status.toUpperCase(), Colors.white.withValues(alpha: 0.2), Colors.white),
                                    if (expiryDate != null && expiryDate!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      _buildBadge("EXP: ${_formatDate(expiryDate)}", Colors.white.withValues(alpha: 0.1), Colors.white.withValues(alpha: 0.8)),
                                    ],
                                  ],
                                ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () async {
                                  try {
                                    await platform.invokeMethod('closeOverlay');
                                  } catch (e) {
                                    debugPrint("Error closing overlay: $e");
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // --- Content Section ---
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isPersonal && customerDetails.isNotEmpty) ...[
                                // --- Customer Details Section (Directly Visible) ---
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.info_outline, size: 14, color: Color(0xFF7986CB)),
                                      const SizedBox(width: 8),
                                      const Text(
                                        "CUSTOMER DETAILS",
                                        style: TextStyle(
                                          color: Color(0xFF7986CB),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: () {
                                      final entries = customerDetails.entries
                                          .where((e) =>
                                              e.value != null &&
                                              e.value.toString().isNotEmpty &&
                                              !['history', 'id', 'created_at', 'active_details']
                                                  .contains(e.key.toLowerCase()))
                                          .toList();
                                      entries.sort((a, b) => a.value.toString().length.compareTo(b.value.toString().length));
                                      return entries.map((e) => _buildDetailChip(e.key, e.value.toString())).toList();
                                    }(),
                                  ),
                                ),
                              ],

                              if (isPersonal)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10),
                                    child: Text(
                                      "No CRM records found for this number.",
                                      style: TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic),
                                    ),
                                  ),
                                ),

                              // --- Progress Bar ---
                              if (_isLookupInProgress) ...[
                                const SizedBox(height: 16),
                                const LinearProgressIndicator(
                                  minHeight: 3,
                                  backgroundColor: Colors.transparent,
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3F51B5)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
        ),
      ],
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return "N/A";
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(dateStr));
    } catch (e) {
      return dateStr;
    }
  }

  Widget _buildBadge(String label, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: textColor, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildDetailChip(String key, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EAF6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _cleanKey(key).toUpperCase(),
            style: const TextStyle(fontSize: 8, color: Color(0xFF7986CB), fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2C2C2C)),
          ),
        ],
      ),
    );
  }
}

class _DancingDots extends StatefulWidget {
  const _DancingDots();
  @override
  State<_DancingDots> createState() => _DancingDotsState();
}

class _DancingDotsState extends State<_DancingDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final delay = index * 0.2;
            final value = (sin((_controller.value * 2 * pi) - (delay * 2 * pi)) + 1) / 2;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFF3F51B5).withValues(alpha: 0.3 + (value * 0.7)),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}
