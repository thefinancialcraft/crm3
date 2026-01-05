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
import 'overlay/main_overlay.dart' as overlay;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await StorageService.init();
  try {
    await dotenv.load(fileName: kIsWeb ? "assets/.env" : ".env");
  } catch (_) {}
  if (AppConstants.supabaseUrl.isNotEmpty &&
      AppConstants.supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
  }
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
        title: 'TFC Nexus',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
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
