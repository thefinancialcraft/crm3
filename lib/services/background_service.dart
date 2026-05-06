import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'call_log_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants.dart';
import 'logger_service.dart';
import 'storage_service.dart';

@pragma('vm:entry-point')
class BackgroundService {
  static const notificationChannelId = 'call_log_sync_channel';
  static const notificationId = 1001;
  static const notificationTitle = 'Call Log Service';

  static Future<void> setup() async {
    // Background service is not supported on web
    if (kIsWeb) {
      LoggerService.info('BackgroundService.setup skipped on Web');
      return;
    }

    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      LoggerService.info('BackgroundService is already running');
      return;
    }

    // Set up notification channel for Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'Call Log Service',
      description: 'Monitors and syncs call logs',
      importance: Importance.high,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    // Initialize notifications plugin with proper settings
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher'),
      ),
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    LoggerService.info('BackgroundService.setup');
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: true,
        autoStart: true,
        autoStartOnBoot: true,
        notificationChannelId: notificationChannelId,
        // Visible persistent notification
        initialNotificationTitle: 'CRM Service',
        initialNotificationContent: 'App running in background',
        // Use a different ID for system notification to avoid conflicts
        foregroundServiceNotificationId: 999,
      ),
      iosConfiguration: IosConfiguration(
        onForeground: onStart,
        onBackground: _onIosBackground,
        autoStart: true,
      ),
    );
    service.startService();
  }

  static Future<void> stop() async {
    if (kIsWeb) return;
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stop');
      LoggerService.info('🛑 BackgroundService stop command sent');
    }
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    LoggerService.info('BackgroundService iOS background execution');
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {

    // ✅ STEP 1 — Binding SABSE PEHLE (Timer se pehle)
    WidgetsFlutterBinding.ensureInitialized();

    // ✅ STEP 2 — Periodic timer (binding ke baad)
    service.on('stop_service').listen((event) => service.stopSelf());

    Timer.periodic(const Duration(minutes: 1), (timer) async {
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: "CRM Service",
          content: "App running in background",
        );
      }
      service.invoke('update');
    });

    // ✅ STEP 3 — Hive init with double-init protection
    try {
      await Hive.initFlutter();
    } catch (e) {
      LoggerService.warn('Hive already initialized: $e');
    }

    // ✅ STEP 4 — StorageService init (isBoxOpen check se)
    try {
      await StorageService.init();
      LoggerService.info('StorageService initialized in background');
      
      // 🔄 Sync user session from SharedPreferences to Hive for cross-isolate reliability
      try {
        final prefs = await SharedPreferences.getInstance();
        final bgUserInfo = prefs.getString('bg_user_info');
        if (bgUserInfo != null) {
          final Map<String, dynamic> payload = jsonDecode(bgUserInfo);
          await StorageService.meta.put('userInfo', payload);
          await StorageService.meta.put('isLoggedIn', prefs.getBool('bg_is_logged_in') ?? true);
          if (payload['organization_id'] != null) {
            await StorageService.meta.put('lastOrgId', payload['organization_id']);
          }
          LoggerService.info('✅ Synced User Data to Background Isolate Storage');
        }
      } catch (e) {
        LoggerService.warn('Failed to sync user data from SharedPreferences: $e');
      }
    } catch (e) {
      LoggerService.warn('StorageService init warning: $e');
    }

    // ✅ STEP 5 — Notifications
    try {
      const channel = AndroidNotificationChannel(
        notificationChannelId, 'Call Log Service',
        description: 'Monitors and syncs call logs',
        importance: Importance.high,
      );
      final notifications = FlutterLocalNotificationsPlugin();
      await notifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_launcher'),
        ),
      );
      await notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    } catch (e) {
      LoggerService.error('Notifications init failed', e);
    }

    // ✅ STEP 6 — Supabase init with double-init protection
    try {
      Supabase.instance.client; // Already initialized hai to exception throw karega
      LoggerService.info('Supabase already initialized in background');
    } catch (_) {
      // Nahi tha, ab initialize karo
      try {
        await Supabase.initialize(
          url: AppConstants.supabaseUrl,
          anonKey: AppConstants.supabaseAnonKey,
        );
        LoggerService.info('Supabase initialized in background isolate');
      } catch (e) {
        LoggerService.warn('Supabase init issue (possibly no GMS or network): $e');
        // App continues to run, as core features might work without Realtime/GMS
      }
    }

    // ✅ STEP 7 — Call service start
    final callSvc = CallLogService();
    await callSvc.initializeCallStateListener();
    callSvc.startAutoSync();

    service.on('stop').listen((event) {
      callSvc.disposeCallStateListener();
      service.stopSelf();
    });
  }
}
