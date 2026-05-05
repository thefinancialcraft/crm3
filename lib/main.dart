import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'providers/sync_provider.dart';
import 'services/storage_service.dart';
import 'constants.dart';
import 'services/logger_service.dart';
import 'package:flutter/services.dart';
import 'overlay/main_overlay.dart' as overlay;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  debugPrint("🚀 Main: Widgets initialized");


  try {
    debugPrint("🚀 Main: Initializing Hive...");
    await Hive.initFlutter().timeout(const Duration(seconds: 5));
    debugPrint("🚀 Main: Initializing Storage...");
    await StorageService.init().timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint("⚠️ Initialization Error: $e");
  }

  try {
    await dotenv.load(fileName: kIsWeb ? "assets/.env" : ".env").timeout(const Duration(seconds: 3));
  } catch (_) {}

  if (AppConstants.supabaseUrl.isNotEmpty && AppConstants.supabaseAnonKey.isNotEmpty) {
    try {
      debugPrint("🚀 Main: Initializing Supabase...");
      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        anonKey: AppConstants.supabaseAnonKey,
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint("⚠️ Supabase Error: $e");
    }
  }

  debugPrint("🚀 Main: Running App...");
  // Permissions, Background Service and Call State Listener will be initialized
  // in InAppWebViewPage after consent and permissions are granted.

  runApp(const RootApp());
}

class RootApp extends StatelessWidget {
  const RootApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => SyncProvider())],
      child: MaterialApp(
        navigatorKey: LoggerService.navKey,
        title: 'Rynxly CRM',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4B33E8)),
          useMaterial3: true,
        ),
        home: const App(),
      ),
    );
  }
}

// Overlay Entry Point
@pragma("vm:entry-point")
void overlayMain() {
  overlay.overlayMain();
}
