import 'package:flutter/material.dart';

class BrandedLoading extends StatelessWidget {
  final double? progress;
  final String? message;

  const BrandedLoading({
    super.key, 
    this.progress,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo.jpeg',
              height: 70,
              errorBuilder: (context, error, stackTrace) => const Text(
                "RYNXLY",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4B33E8),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: null, // Continuously moving indicator
                  backgroundColor: const Color(0xFFF0F0F0),
                  color: const Color(0xFF4B33E8),
                  minHeight: 4,
                ),
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(
                message!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
