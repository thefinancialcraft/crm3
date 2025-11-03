import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'providers/sync_provider.dart';
import 'services/storage_service.dart';
import 'services/background_service.dart';
import 'constants.dart';
import 'services/permission_service.dart';
import 'services/logger_service.dart';
import 'services/call_log_service_v2.dart' as v2;

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
  await PermissionService.requestEssential();
  
  // Initialize background service for both Android and iOS
  if (!kIsWeb) {
    await BackgroundService.setup();
  }
  
  // Initialize call state listener when app has UI
  _startCallStateListener();
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
        title: 'Call Log Uploader',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        ),
        home: const App(),
      ),
    );
  }
}

// Global CallLogService instance for real-time call state tracking
final _callLogService = v2.CallLogService();

// Start call state listener once the app frame is ready
void _startCallStateListener() {
  try {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initialize real-time call state listener (like Truecaller)
      _callLogService.initializeCallStateListener();
      LoggerService.info('Call state listener initialized');
    });
  } catch (_) {}
}