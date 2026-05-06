import 'package:flutter/material.dart';
import '../widgets/branded_loading.dart';

class CrmInitPage extends StatelessWidget {
  final double? progress;
  final String message;

  const CrmInitPage({
    super.key,
    this.progress,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: BrandedLoading(
        progress: progress,
        message: message,
      ),
    );
  }
}
