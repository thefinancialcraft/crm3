import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
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

  String number = "Unknown";
  String name = "";
  String status = "Connecting...";
  bool isPersonal = true;

  @override
  void initState() {
    super.initState();

    /// Listen for data from Native Service
    platform.setMethodCallHandler((call) async {
      if (call.method == "updateData") {
        final args = call.arguments;
        if (args is Map) {
          if (mounted) {
            setState(() {
              number = args['number'] ?? number;
              status = args['status'] ?? status;
              isPersonal = args['isPersonal'] ?? isPersonal;
              if (args['name'] != null) name = args['name'];
            });
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(color: Colors.grey.shade200, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header (Compact)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.hub_rounded,
                        size: 12,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "TFC NEXUS",
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () async {
                          await platform.invokeMethod('closeOverlay');
                        },
                        icon: const Icon(Icons.close_rounded, size: 16),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                      ),
                    ],
                  ),
                ),

                // Main Content (Row Layout)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Avatar (Slightly smaller)
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

                      // Name/Number & Badges
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
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1F2937),
                                  height: 1.1,
                                ),
                              ),
                            Text(
                              number,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Badges Row
                            Row(
                              children: [
                                _badge(
                                  isPersonal ? "Personal" : "Customer",
                                  isPersonal
                                      ? const Color(0xFFF59E0B)
                                      : const Color(0xFF10B981),
                                ),
                                const SizedBox(width: 6),
                                _badge(
                                  status.toUpperCase(),
                                  const Color(0xFF6366F1),
                                ),
                              ],
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
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
