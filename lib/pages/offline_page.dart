import 'package:flutter/material.dart';

class OfflinePage extends StatelessWidget {
  final VoidCallback? onReload;

  const OfflinePage({super.key, this.onReload});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF5E17EB);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.05), shape: BoxShape.circle),
                child: const Icon(Icons.wifi_off_rounded, size: 80, color: primaryColor),
              ),
              const SizedBox(height: 40),
              const Text('Connection Lost', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87, letterSpacing: -1)),
              const SizedBox(height: 12),
              const Text('Your device is currently offline. Please check your network and tap reload.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.grey, height: 1.5)),
              const SizedBox(height: 50),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: onReload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('RELOAD SYSTEM', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
