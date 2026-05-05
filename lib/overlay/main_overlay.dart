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

class _CallOverlayScreenBodyState extends State<_CallOverlayScreenBody> with TickerProviderStateMixin {
  final MethodChannel platform = const MethodChannel('com.example.crm3/overlay');
  final SyncService _syncSvc = SyncService.instance;
  final GlobalKey _columnKey = GlobalKey();
  final GlobalKey _bubbleKey = GlobalKey();

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
  String? _lastProcessedNumber; // 🛡️ Anti-double-init guard

  // --- Animation Controllers ---
  late AnimationController _bubbleController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _widthAnimation;
  late Animation<double> _contentOpacity;
  late Animation<double> _rotationAnimation; // 🚀 New: Icon rotation

  @override
  void initState() {
    super.initState();
    
    // --- Initialize Bubble Animation ---
    _bubbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800), // 🚀 Faster expansion/shrink
    );

    _scaleAnimation = CurvedAnimation(
      parent: _bubbleController,
      curve: Interval(0.0, 0.4, curve: Curves.easeOutBack),
    );

    _widthAnimation = CurvedAnimation(
      parent: _bubbleController,
      curve: Interval(0.4, 0.8, curve: Curves.easeInOutQuart),
    );

    _rotationAnimation = Tween<double>(begin: 60 * (pi / 180), end: 0.0).animate(
      CurvedAnimation(
        parent: _bubbleController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutQuart),
      ),
    );

    _contentOpacity = CurvedAnimation(
      parent: _bubbleController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeIn),
    );

    // Initial play will happen when lookup starts or during getInitialData
    // We don't call forward() here anymore to let _performLocalLookup handle it

    // 🚀 DELAY Bridge setup slightly to avoid race conditions with late fields
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _setupMethodChannel();
        _getInitialData();
      }
    });
  }

  @override
  void dispose() {
    _bubbleController.dispose();
    super.dispose();
  }

  void _updateUI(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    _safeUpdateHeight();
  }

  Widget _buildLoadingBubble() {
    return AnimatedBuilder(
      animation: _bubbleController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            key: _bubbleKey,
            height: 50,
            constraints: BoxConstraints(
              minWidth: 50,
              maxWidth: 50 + (140 * _widthAnimation.value), // Expands from circle to pill
            ),
            padding: EdgeInsets.symmetric(
              horizontal: 15 * _scaleAnimation.value,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15 * _scaleAnimation.value),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Opacity(
                opacity: _contentOpacity.value,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.rotate(
                      angle: _rotationAnimation.value,
                      child: const Icon(Icons.search, size: 22, color: Color(0xFF3F51B5)),
                    ),
                    if (_widthAnimation.value > 0.5) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
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
          _lastProcessedNumber = null; 
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
        if (name.isEmpty && number != "Unknown" && number.isNotEmpty && !_isLookupInProgress && number != _lastProcessedNumber) {
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
    final startTime = DateTime.now(); // ⏱️ Track start time
    
    debugPrint("[OverlayLookup] Starting lookup for: $lookupNumber (Attempt $attempt)");
    if (lookupNumber == "Unknown" || lookupNumber.isEmpty) return;

    if (_isLookupInProgress && attempt == 1) {
      debugPrint("[OverlayLookup] Lookup already in progress, skipping.");
      return;
    }
    
    if (_lastProcessedNumber == lookupNumber && attempt == 1 && _showFullCard) {
      debugPrint("[OverlayLookup] Number already processed and card shown, skipping.");
      return;
    }

    _isLookupInProgress = true;
    _lastProcessedNumber = lookupNumber;
    
    // 🚀 Safety Check: Reset and play bubble animation only if initialized
    try {
      _bubbleController.reset();
      _bubbleController.forward();
    } catch (e) {
      debugPrint("[OverlayLookup] Animation controller not ready yet.");
    }

    try {
      String normalized = lookupNumber.replaceAll(RegExp(r'[^0-9]'), '');
      if (normalized.length > 10) {
        normalized = normalized.substring(normalized.length - 10);
      }
      
      debugPrint("[OverlayLookup] Calling SyncService for: $normalized");
      // 🕒 DB Fetch
      final result = await _syncSvc.lookupCustomer(normalized).timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          debugPrint("[OverlayLookup] TIMEOUT reached for $normalized");
          return null;
        },
      );
      
      // 🛡️ ENFORCE 2.5-SECOND BUBBLE VISIBILITY
      final elapsed = DateTime.now().difference(startTime);
      if (elapsed.inMilliseconds < 2500) {
        final waitTime = 2500 - elapsed.inMilliseconds;
        debugPrint("[OverlayLookup] Enforcing bubble for another ${waitTime}ms");
        await Future.delayed(Duration(milliseconds: waitTime));
      }

      // 🚀 SHRINK BUBBLE BACK TO DOT BEFORE SHOWING CARD
      debugPrint("[OverlayLookup] Shrinking bubble back to dot...");
      try {
        await _bubbleController.reverse();
      } catch (e) {
        debugPrint("[OverlayLookup] Shrink animation failed: $e");
      }
      
      debugPrint("[OverlayLookup] Result received: ${result != null ? 'DATA FOUND' : 'NULL'}");
      
      final String currentClean = number.replaceAll(RegExp(r'[^0-9]'), '').split('').reversed.take(10).toList().reversed.join();
      final String lookupClean = lookupNumber.replaceAll(RegExp(r'[^0-9]'), '').split('').reversed.take(10).toList().reversed.join();

      if (!mounted || (currentClean != lookupClean && lookupClean.isNotEmpty)) {
        debugPrint("[OverlayLookup] Context unmounted or logical number changed ($lookupClean -> $currentClean), aborting UI update.");
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
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              switchInCurve: Curves.linear,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (Widget child, Animation<double> animation) {
                final isCard = child.key == _columnKey;
                if (isCard) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                        CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                      ),
                      child: child,
                    ),
                  );
                } else {
                  return FadeTransition(opacity: animation, child: child);
                }
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
                                  colors: status.toLowerCase() == 'rejected'
                                      ? [const Color(0xFFD32F2F), const Color(0xFFEF5350)] // 🔴 Rejected
                                      : (status.toLowerCase().contains('followup')
                                          ? [const Color(0xFFFF9800), const Color(0xFFFFB74D)] // 🟠 Follow Up
                                          : (status.toLowerCase() == 'closed'
                                              ? [const Color(0xFF4B33E8), const Color(0xFF6A54F0)] // 🟣 Closed
                                              : (isPersonal
                                                  ? [const Color(0xFF43A047), const Color(0xFF66BB6A)] // 🟢 Personal
                                                  : [const Color(0xFF3F51B5), const Color(0xFF5C6BC0)]))), // 🔵 Customer
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(14), // 🚀 Increased from 10
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.person, color: Colors.white, size: 30), // 🚀 Increased from 24
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
                                                  : "Personal Contact")
                                              : (name.isEmpty
                                                  ? "Unknown Caller"
                                                  : (name.length > 15 ? "${name.substring(0, 15)}..." : name)),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
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
                                        const SizedBox(height: 5), // 🚀 Decreased from 8
                                        if (!isPersonal)
                                          Row(
                                            children: [
                                              _buildBadge(status.toUpperCase(), Colors.white.withValues(alpha: 0.1),
                                                  Colors.white.withValues(alpha: 0.8)),
                                              if (expiryDate != null && expiryDate!.isNotEmpty) ...[
                                                const SizedBox(width: 8),
                                                _buildBadge("EXP: ${_formatDate(expiryDate)}", Colors.white.withValues(alpha: 0.1),
                                                    Colors.white.withValues(alpha: 0.8)),
                                              ],
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  GestureDetector(
                                    onTap: () async {
                                      try {
                                        _updateUI(() {
                                          _lastProcessedNumber = null;
                                          _isLookupInProgress = false;
                                          _showFullCard = false;
                                        });
                                        await platform.invokeMethod('closeOverlay');
                                      } catch (e) {
                                        debugPrint("Error closing overlay: $e");
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(10), // 🚀 Increased from 8
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close, color: Colors.white, size: 24), // 🚀 Increased from 20
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
                                          entries.sort((a, b) =>
                                              a.value.toString().length.compareTo(b.value.toString().length));
                                          return entries
                                              .map((e) => _buildDetailChip(e.key, e.value.toString()))
                                              .toList();
                                        }(),
                                      ),
                                    ),
                                  ],
                                  if (status.toLowerCase() == 'rejected')
                                    _buildFooterMessage("This is a rejected lead or Not Interested", const Color(0xFFD32F2F)),
                                  if (status.toLowerCase() == 'closed')
                                    _buildFooterMessage("This lead is already closed", const Color(0xFF4B33E8)),
                                  if (isPersonal && status.toLowerCase() != 'rejected' && status.toLowerCase() != 'closed')
                                    _buildFooterMessage("No CRM records found for this number.", Colors.grey),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooterMessage(String message, Color color) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 14, // 🚀 Increased size
            fontWeight: FontWeight.w600,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
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
