import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../services/sync_service.dart';
import '../constants.dart';

@pragma("vm:entry-point")
Future<void> overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
  } catch (e) {
    print('[_from_overlay] ❌ Supabase init error: $e');
  }
  runApp(const CallOverlayApp());
}

class CallOverlayApp extends StatelessWidget {
  const CallOverlayApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1)),
      ),
      home: const CallOverlayScreen(),
    );
  }
}

class CallOverlayScreen extends StatefulWidget {
  const CallOverlayScreen({super.key});
  @override
  State<CallOverlayScreen> createState() => _CallOverlayScreenState();
}

class _CallOverlayScreenState extends State<CallOverlayScreen> {
  static const platform = MethodChannel('com.example.crm3/overlay');
  final _syncSvc = SyncService.instance;

  String number = "Unknown";
  String name = "";
  String status = "Connecting...";
  String? expiryDate;
  Map<String, dynamic> customerDetails = {};
  bool isPersonal = true;
  bool _isLookupInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _getInitialData());

    platform.setMethodCallHandler((call) async {
      if (call.method == "updateData" || call.method == "updateLookupResult") {
        final args = call.arguments;
        if (args is Map && mounted) {
          final String newNumber = args['number'] ?? number;
          setState(() {
            if (newNumber != number &&
                newNumber != "Unknown" &&
                newNumber.isNotEmpty) {
              name = "";
              isPersonal = true;
              expiryDate = null;
              customerDetails = {};
              _isLookupInProgress = false;
            }
            number = newNumber;
            status = args['status'] ?? status;
            if (args['name'] != null && args['name'].toString().isNotEmpty) {
              name = args['name'];
              isPersonal = false;
              expiryDate = args['expiry_date'];
              if (args['customer_details'] is Map) {
                customerDetails = Map<String, dynamic>.from(
                  args['customer_details'],
                );
              } else if (args['customer_details'] is String) {
                try {
                  customerDetails = jsonDecode(args['customer_details']);
                } catch (_) {}
              }
            }
          });
          if (name.isEmpty &&
              number != "Unknown" &&
              number.isNotEmpty &&
              !_isLookupInProgress)
            _performLocalLookup();
        }
      }
      return null;
    });
  }

  Future<void> _getInitialData() async {
    try {
      final String? nativeNo = await platform.invokeMethod('getNativeNumber');
      final dynamic preData = await platform.invokeMethod('getPreStartData');
      if (mounted) {
        setState(() {
          if (preData is Map) {
            number = preData['number'] ?? nativeNo ?? number;
            name = preData['name'] ?? "";
            status = preData['status'] ?? status;
            isPersonal = preData['isPersonal'] ?? isPersonal;
            expiryDate = preData['expiry_date'];
            if (preData['customer_details'] is Map)
              customerDetails = Map<String, dynamic>.from(
                preData['customer_details'],
              );
          } else if (nativeNo != null && nativeNo.isNotEmpty) {
            number = nativeNo;
            isPersonal = true;
          }
        });
        if (name.isEmpty && number != "Unknown" && number.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 500));
          _performLocalLookup();
        }
      }
    } catch (e) {}
  }

  Future<void> _performLocalLookup({int attempt = 1}) async {
    if (_isLookupInProgress && attempt == 1) return;
    _isLookupInProgress = true;
    try {
      String normalized = number.replaceAll(RegExp(r'[^0-9]'), '');
      if (normalized.length > 10)
        normalized = normalized.substring(normalized.length - 10);
      final result = await _syncSvc.lookupCustomer(normalized);
      if (!mounted) return;
      if (result != null) {
        setState(() {
          name = result['customer_name'] ?? "";
          isPersonal = false;
          expiryDate = result['expiry_date'];
          if (result['customer_details'] is Map)
            customerDetails = Map<String, dynamic>.from(
              result['customer_details'],
            );
          _isLookupInProgress = false;
        });
      } else if (attempt < 3) {
        await Future.delayed(Duration(milliseconds: attempt * 700));
        _performLocalLookup(attempt: attempt + 1);
      } else {
        setState(() {
          isPersonal = true;
          name = "";
          _isLookupInProgress = false;
        });
      }
    } catch (e) {
      _isLookupInProgress = false;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return "";
    try {
      return DateFormat('dd/MM/yy').format(DateTime.parse(dateStr));
    } catch (_) {
      return dateStr;
    }
  }

  String _cleanKey(String key) => key
      .replaceAll('_checked', '')
      .replaceAll('_unchecked', '')
      .replaceAll('_', ' ')
      .toUpperCase();

  @override
  Widget build(BuildContext context) {
    final cleanDetails = customerDetails.entries
        .map((e) => MapEntry(_cleanKey(e.key), e.value))
        .toList();

    return Material(
      color: Colors.transparent,
      child: Container(
        // Use a container with a background loosely to avoid full-screen trapping
        // but the actual content is in the Column.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 👆 DRAG HANDLE
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isPersonal
                                  ? [
                                      const Color(0xFFF59E0B),
                                      const Color(0xFFD97706),
                                    ]
                                  : [
                                      const Color(0xFF10B981),
                                      const Color(0xFF059669),
                                    ],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : "?",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (name.isNotEmpty)
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              Text(
                                number,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _badge(
                                      isPersonal ? "PERSONAL" : "CUSTOMER",
                                      isPersonal ? Colors.orange : Colors.green,
                                    ),
                                    const SizedBox(width: 6),
                                    _badge(status.toUpperCase(), Colors.indigo),
                                    if (expiryDate != null) ...[
                                      const SizedBox(width: 6),
                                      _badge(
                                        "EXP: ${_formatDate(expiryDate)}",
                                        Colors.red.shade700,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () async {
                            print('[_from_overlay] 🛑 Close clicked');
                            try {
                              await platform.invokeMethod('closeOverlay');
                            } catch (e) {
                              print('[_from_overlay] ❌ Close error: $e');
                            }
                          },
                          icon: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isPersonal && cleanDetails.isNotEmpty) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                size: 14,
                                color: Colors.indigo,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                "CUSTOMER DETAILS",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.indigo,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: cleanDetails.map((detail) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.indigo.withValues(alpha: 0.1),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      detail.key,
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo.shade300,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      detail.value.toString(),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w800),
    ),
  );
}
