import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/consent_service.dart';
import 'permissions_page.dart';

class ConsentPage extends StatefulWidget {
  const ConsentPage({super.key});

  @override
  State<ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<ConsentPage> {
  bool isChecked = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri)) {
      debugPrint("Could not launch $url");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    /// 🔷 Logo + Title
                    Center(
                      child: Column(
                        children: [
                          Image.asset(
                            'assets/app_icon.png', // updated logo path
                            height: 60,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "Welcome to Rynxly CRM",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      "Rynxly CRM is a SIM-based calling CRM that helps you track calls, manage leads, and improve customer interactions in real-time.",
                      style: TextStyle(fontSize: 15),
                    ),

                    const SizedBox(height: 24),

                    /// 🔐 Permissions Section
                    const Text(
                      "Permissions Required",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4B33E8),
                      ),
                    ),
                    const SizedBox(height: 12),

                    _feature(
                      Icons.call,
                      "Call Logs & Phone State",
                      "Track incoming, outgoing, and missed calls",
                    ),
                    _feature(
                      Icons.person,
                      "Phone Number Access",
                      "Identify customers and link calls with leads",
                    ),
                    _feature(
                      Icons.layers,
                      "Overlay Permission",
                      "Show real-time call popup with customer details",
                    ),
                    _feature(
                      Icons.sync,
                      "Background Activity",
                      "Ensure continuous call tracking and syncing",
                    ),

                    const SizedBox(height: 24),

                    /// 🔒 Privacy Section
                    const Text(
                      "Your Privacy",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4B33E8),
                      ),
                    ),
                    const SizedBox(height: 12),

                    const Text(
                      "Data Privacy & Security",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1C1710),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "We maintain a strict isolation policy: your personal call records and private data are never tracked or accessed. Rynxly CRM exclusively synchronizes business-specific telephony data required for your CRM operations. All information is encrypted and processed under the highest security standards to ensure your confidentiality.",
                      style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
                    ),

                    const SizedBox(height: 20),

                    /// 🔗 Links
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () =>
                              _openUrl("https://www.rynxly.in/privacy-policy"),
                          child: const Text(
                            "Privacy Policy",
                            style: TextStyle(
                              color: Color(0xFF4B33E8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () => _openUrl("https://www.rynxly.in/terms"),
                          child: const Text(
                            "Terms of Service",
                            style: TextStyle(
                              color: Color(0xFF4B33E8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            /// 🔻 Bottom Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: isChecked,
                        onChanged: (val) {
                          setState(() => isChecked = val ?? false);
                        },
                      ),
                      const Expanded(
                        child: Text(
                          "I agree to the Privacy Policy & Terms and allow Rynxly CRM to process call-related data for CRM functionality.",
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: const BorderSide(color: Colors.grey),
                            foregroundColor: Colors.black87,
                          ),
                          onPressed: () => SystemNavigator.pop(),
                          child: const Text(
                            "Decline",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4B33E8),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFF4B33E8).withValues(alpha: 0.5),
                            disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: isChecked
                              ? () async {
                                  await ConsentService.markConsentAccepted();
                                  if (!context.mounted) return;

                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const PermissionsPage(),
                                    ),
                                  );
                                }
                              : null,
                          child: const Text(
                            "Accept & Continue",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feature(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF4B33E8)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(desc, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
