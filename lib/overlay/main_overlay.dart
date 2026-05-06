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
  String? subDisposition;
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
  late AnimationController _pulseController; // 🚀 New: Close button wave

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

    // --- Pulse Animation for Close Button ---
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

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
    _pulseController.dispose();
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
      try {
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
          return null;
        }

        if (call.method == "updateData" || call.method == "updateLookupResult") {
          final args = call.arguments;
          debugPrint("[OverlayChannel] Arguments: $args");
          if (args is Map && mounted) {
            final String incomingNo = args['number']?.toString() ?? number;
            
            final String cleanNew = _normalize(incomingNo);
            final String cleanOld = _normalize(number);

            final bool hasIncomingName = args['name'] != null && 
                                        args['name'].toString().isNotEmpty && 
                                        args['name'] != "Searching...";

            _updateUI(() {
              if (cleanNew != cleanOld && cleanNew.isNotEmpty) {
                debugPrint("[OverlayChannel] New number detected: $incomingNo");
                
                // 🚀 ALWAYS START WITH BUBBLE for new numbers (User Requirement)
                _showFullCard = false;
                _isLookupInProgress = false;
                
                // Preserve what we can from args, but keep card hidden for now
                name = hasIncomingName ? args['name'] : "";
                isPersonal = args['isPersonal'] ?? true;
                customerDetails = hasIncomingName ? _parseDetails(args['customer_details']) : {};
                contactNameFromPhone = args['contactName']?.toString();
                expiryDate = null;
                number = incomingNo;
              } else {
                // Same number, update status or supplementary details
                number = incomingNo;
                if (args['contactName'] != null) {
                   contactNameFromPhone = args['contactName'].toString();
                }
              }

              status = args['status'] ?? status;
              subDisposition = args['sub_disposition']?.toString();
              
              // If data arrives for the current number, update it
              if (hasIncomingName) {
                debugPrint("[OverlayChannel] Data received for $number: ${args['name']}");
                name = args['name'];
                isPersonal = args['isPersonal'] ?? false;
                expiryDate = args['expiry_date']?.toString();
                customerDetails = _parseDetails(args['customer_details']);
                
                // Only reveal card if lookup has already completed
                // Otherwise _performLocalLookup will handle the reveal after its 2.5s window
                if (_normalize(_lastProcessedNumber ?? "") == cleanNew && !_isLookupInProgress) {
                  _showFullCard = true;
                }
              }
            });
            
            // Trigger local lookup for new numbers
            if (number != "Unknown" && number.isNotEmpty && !_isLookupInProgress) {
              _performLocalLookup();
            }
          }
        }
      } catch (e, stack) {
        debugPrint("[OverlayChannel] Error in MethodCallHandler: $e\n$stack");
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
            if (preData['customer_details'] != null) {
              customerDetails = _parseDetails(preData['customer_details']);
            }
            // 🚀 Force bubble state even if data is present
            _showFullCard = false;
          } else if (nativeNo != null) {
            number = nativeNo;
          }
        });
        
        // 🚀 Always trigger lookup for valid numbers to handle the 2.5s delay and transition
        if (number != "Unknown" && number.isNotEmpty && !_isLookupInProgress) {
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
    
    if (_normalize(_lastProcessedNumber ?? "") == _normalize(lookupNumber) && attempt == 1 && _showFullCard) {
      debugPrint("[OverlayLookup] Number already processed and card shown, skipping.");
      return;
    }

    _isLookupInProgress = true;
    _lastProcessedNumber = lookupNumber;
    
    // 🚀 ALWAYS reset and play bubble animation for new lookup starts (User Requirement)
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
      
      // 🧹 CLEAR CACHE: Ensure we don't show "purana record" (old data)
      _syncSvc.clearCustomerCache(normalized);
      
      // 🕒 DB Fetch (Do it in parallel with the enforced bubble delay)
      final result = await _syncSvc.lookupCustomer(normalized).timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          debugPrint("[OverlayLookup] TIMEOUT reached for $normalized");
          return null;
        },
      );
      
      // 🛡️ ENFORCE 2.5-SECOND BUBBLE VISIBILITY (Consistency check)
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
      
      final String currentClean = _normalize(number);
      final String lookupClean = _normalize(lookupNumber);

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
          subDisposition = result['sub_disposition']?.toString();
          expiryDate = result['expiry_date']?.toString();
          
          customerDetails = _parseDetails(result['customer_details']);

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
                        child: Stack(
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // --- Header Section ---
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight, 
                                      colors: status.toLowerCase() == 'rejected' || status.toLowerCase() == 'junk'
                                          ? [const Color(0xFFD32F2F), const Color(0xFFEF5350)] // 🔴 Rejected / Junk (Red)
                                          : (status.toLowerCase().contains('followup')
                                              ? [const Color(0xFFFF9800), const Color(0xFFFFB74D)] // 🟠 Follow Up (Orange)
                                              : (status.toLowerCase() == 'closed' || status.toLowerCase() == 'won'
                                                  ? [const Color(0xFF3F51B5), const Color(0xFF5C6BC0)] // 🟣 Closed / Won (Indigo)
                                                  : (isPersonal
                                                      ? [const Color(0xFF43A047), const Color(0xFF66BB6A)] // 🟢 Personal (Green)
                                                      : [const Color(0xFF4B33E8), const Color(0xFF6A54F0)]))), // 🔵 Customer (Blue)
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.2),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.person, color: Colors.white, size: 28),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  isPersonal
                                                      ? (contactNameFromPhone?.isNotEmpty == true
                                                          ? (contactNameFromPhone!.length > 18
                                                              ? "${contactNameFromPhone!.substring(0, 18)}..."
                                                              : contactNameFromPhone!)
                                                          : "Personal Contact")
                                                      : (name.isEmpty
                                                          ? "Unknown Caller"
                                                          : (name.length > 18 ? "${name.substring(0, 18)}..." : name)),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                                Text(
                                                  number,
                                                  style: TextStyle(
                                                    color: Colors.white.withValues(alpha: 0.8),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _buildPulseCloseButton(),
                                        ],
                                      ),
                                      if (!isPersonal) ...[
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          child: Container(
                                            height: 1,
                                            color: Colors.white.withValues(alpha: 0.15),
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            _buildBadge(status.toUpperCase(), Colors.white.withValues(alpha: 0.1),
                                                Colors.white.withValues(alpha: 0.8)),
                                            if (subDisposition != null && subDisposition!.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              _buildBadge(subDisposition!.toUpperCase(), Colors.white.withValues(alpha: 0.1),
                                                  Colors.white.withValues(alpha: 0.8)),
                                            ],
                                            if (expiryDate != null && expiryDate!.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              _buildBadge("EXP: ${_formatDate(expiryDate)}", Colors.white.withValues(alpha: 0.1),
                                                  Colors.white.withValues(alpha: 0.8)),
                                            ],
                                          ],
                                        ),
                                      ],
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
                                      if (status.toLowerCase() == 'rejected' || 
                                          status.toLowerCase() == 'closed' || 
                                          (isPersonal && status.toLowerCase() != 'rejected' && status.toLowerCase() != 'closed'))
                                        const SizedBox(height: 10), // Small spacer instead of full footer
                                      // Add spacing to prevent logo overlap if content is short
                                      const SizedBox(height: 20),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            // 🚀 Footer Message + Logo at Bottom
                            Positioned(
                              bottom: 10,
                              left: 20,
                              right: 10,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // 📝 Footer Text (Left Aligned)
                                  Expanded(
                                    child: () {
                                      String msg = "";
                                      Color col = Colors.grey;
                                      if (status.toLowerCase() == 'rejected') {
                                        msg = "This lead is Rejected or Not Interested";
                                        col = const Color(0xFFD32F2F);
                                      } else if (status.toLowerCase() == 'closed') {
                                        msg = "This lead is already Closed";
                                        col = const Color(0xFF3F51B5);
                                      } else if (isPersonal) {
                                        msg = "No CRM records found for this number";
                                        col = Colors.grey.shade500;
                                      }
                                      
                                      if (msg.isEmpty) return const SizedBox.shrink();
                                      
                                      return Opacity(
                                        opacity: 0.9,
                                        child: Text(
                                          msg,
                                          style: TextStyle(
                                            color: col,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      );
                                    }(),
                                  ),
                                  // 🎨 Logo (Right Aligned)
                                  Opacity(
                                    opacity: 0.6,
                                    child: Image.asset(
                                      'assets/images/logo.jpeg',
                                      height: 30,
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) => Text(
                                        "RYNXLY",
                                        style: TextStyle(
                                          color: const Color(0xFF3F51B5).withValues(alpha: 0.3),
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
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

  Map<String, dynamic> _parseDetails(dynamic raw) {
    if (raw == null) {
      debugPrint("[OverlayParse] Raw details is null");
      return {};
    }
    Map<String, dynamic> parsed = {};
    try {
      if (raw is String && raw.isNotEmpty) {
        parsed = Map<String, dynamic>.from(jsonDecode(raw));
      } else if (raw is Map) {
        parsed = Map<String, dynamic>.from(raw);
      } else {
        debugPrint("[OverlayParse] Unknown raw details type: ${raw.runtimeType}");
      }

      // 🚀 Extract data from nested 'history' based on 'active_details'
      if (parsed.containsKey('active_details') && parsed.containsKey('history')) {
        final activeKey = parsed['active_details'];
        final history = parsed['history'];
        if (history is Map && history.containsKey(activeKey)) {
          debugPrint("[OverlayParse] Successfully extracted nested details for key: $activeKey");
          return Map<String, dynamic>.from(history[activeKey]);
        }
      }
      
      if (parsed.isEmpty && raw != null) {
        debugPrint("[OverlayParse] Parsed map is empty but raw data exists");
      }
      
      return parsed;
    } catch (e) {
      debugPrint("[OverlayParse] Error parsing details ($raw): $e");
      return parsed.isNotEmpty ? parsed : {};
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return "N/A";
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(dateStr));
    } catch (e) {
      return dateStr;
    }
  }

  String _normalize(String input) {
    if (input.isEmpty || input == "Unknown") return "";
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  Widget _buildPulseCloseButton() {
    return GestureDetector(
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
      child: SizedBox(
        width: 70,
        height: 70,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 🌊 Wave 1 (Primary)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 48 + (22 * _pulseController.value),
                  height: 48 + (22 * _pulseController.value),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4 * (1 - _pulseController.value)),
                      width: 1.5,
                    ),
                  ),
                );
              },
            ),
            // 🌊 Wave 2 (Secondary - Offset by 0.5)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                double wave2Value = (_pulseController.value + 0.5) % 1.0;
                return Container(
                  width: 48 + (22 * wave2Value),
                  height: 48 + (22 * wave2Value),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25 * (1 - wave2Value)),
                      width: 1.2,
                    ),
                  ),
                );
              },
            ),
            // ❌ Refined Static Close Button
            Container(
              padding: const EdgeInsets.all(10), // 🚀 Tightened padding
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 22), // 🚀 Reduced to 22px
            ),
          ],
        ),
      ),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), // 🚀 Compact padding
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FE),
        borderRadius: BorderRadius.circular(8), // 🚀 Slightly smaller radius
        border: Border.all(color: const Color(0xFFE8EAF6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _cleanKey(key).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 7, color: Color(0xFF7986CB), fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            value.length > 12 ? "${value.substring(0, 12)}..." : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF2C2C2C)),
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
