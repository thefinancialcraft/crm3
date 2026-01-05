import 'dart:async';
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
import '../utils/device_utils.dart';

class BackgroundService {
  static const notificationChannelId = 'call_log_sync_channel';
  static const notificationId = 1001;
  static const notificationTitle = 'Call Log Service';
  static FlutterLocalNotificationsPlugin? _notificationsPlugin;

  static Future<void> setup() async {
    // Background service is not supported on web
    if (kIsWeb) {
      LoggerService.info('BackgroundService.setup skipped on Web');
      return;
    }

    final service = FlutterBackgroundService();

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
        android: AndroidInitializationSettings('ic_bg_service_small'),
      ),
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    _notificationsPlugin = flutterLocalNotificationsPlugin;

    LoggerService.info('BackgroundService.setup');
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: true,
        autoStart: true,
        autoStartOnBoot: true,
        notificationChannelId: notificationChannelId,
        // Set empty notification that will be hidden
        initialNotificationTitle: '',
        initialNotificationContent: '',
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

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    LoggerService.info('BackgroundService iOS background execution');
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    LoggerService.info('BackgroundService.onStart');

    // Keep service alive by reporting its still running periodically
    service.on('stop_service').listen((event) {
      service.stopSelf();
    });

    // Ensure this service keeps running
    Timer.periodic(const Duration(minutes: 1), (timer) async {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          // Keep service alive but with minimal UI
          service.setForegroundNotificationInfo(title: "", content: "");
        }
      }
      service.invoke('update');
    });

    // Ensure Flutter bindings and plugins are initialized in background isolate
    try {
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize Hive and Storage for background access
      await Hive.initFlutter();
      await StorageService.init();
      LoggerService.info('Hive & StorageService initialized in background');

      // Re-initialize notifications in background isolate
      final FlutterLocalNotificationsPlugin notifications =
          FlutterLocalNotificationsPlugin();
      await notifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_bg_service_small'),
        ),
      );

      // Create notification channel in background isolate
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        notificationChannelId,
        'Call Log Service',
        description: 'Monitors and syncs call logs',
        importance: Importance.high,
      );

      await notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      _notificationsPlugin = notifications;
      LoggerService.info('Notifications initialized in background isolate');
    } catch (e) {
      LoggerService.error('Failed to initialize background isolate', e);
    }

    // Initialize Supabase in the background isolate so Supabase.instance.client
    // is available here. This mirrors the approach in the working last_version.
    try {
      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        anonKey: AppConstants.supabaseAnonKey,
      );
      LoggerService.info('Supabase initialized in background isolate');
    } catch (e, _) {
      LoggerService.warn(
        'Supabase.initialize in background isolate failed: $e',
      );
    }

    // Set up notifications plugin using the already initialized instance
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        _notificationsPlugin ?? FlutterLocalNotificationsPlugin();

    LoggerService.info(
      'BackgroundService started - notifications will show only during calls',
    );

    // Set up real-time call monitoring
    final callSvc = CallLogService();
    await callSvc.initializeCallStateListener();
    // Start auto sync for continuous background syncing
    callSvc.startAutoSync();

    // Perform initial sync when app is first installed - only last 3 days
    try {
      final isFirstSyncCompleted = await CallLogService.isFirstSyncCompleted();
      if (!isFirstSyncCompleted) {
        LoggerService.info(
          'Performing first sync on app installation (last 3 days only)',
        );
        // Show notification for first sync
        _showBackgroundNotification(
          flutterLocalNotificationsPlugin,
          'Initial setup',
          'Syncing recent call logs',
        );

        // Use scanAndEnqueueNewCalls which already filters to last 3 days
        final callSvc = CallLogService();
        final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
        final newCount = await callSvc.scanAndEnqueueNewCalls();
        LoggerService.info(
          'Enqueued $newCount entries from last 3 days for initial sync',
        );

        if (newCount > 0) {
          // Deduplicate local pending entries against remote Supabase rows for this device
          try {
            final deviceId = await DeviceUtils.getDeviceId();
            LoggerService.info(
              'Deduplicating local entries against Supabase for device $deviceId',
            );

            // Fetch recent remote rows for this device (limit to 3 days window)
            List remoteRows = [];
            try {
              remoteRows =
                  await Supabase.instance.client
                          .from('call_history')
                          .select('number,timestamp,duration,call_type')
                          .eq('device_id', deviceId)
                          .gte(
                            'timestamp',
                            threeDaysAgo.toUtc().toIso8601String(),
                          )
                      as List;
            } catch (e) {
              LoggerService.warn('Failed to fetch remote rows for dedupe: $e');
            }

            final Set<String> existingSet = {};
            for (final r in remoteRows) {
              try {
                final number = r['number']?.toString() ?? '';
                final timestamp = r['timestamp']?.toString() ?? '';
                final duration = r['duration']?.toString() ?? '';
                final callType = r['call_type']?.toString() ?? '';
                existingSet.add(
                  [number, timestamp, duration, callType].join('_'),
                );
              } catch (_) {}
            }

            // Iterate local callBucket and remove any entries already present remotely
            final keys = StorageService.callBucket.keys.toList();
            var removed = 0;
            final nowIso = DateTime.now().toUtc().toIso8601String();
            for (final key in keys) {
              try {
                final raw = StorageService.callBucket.get(key);
                if (raw is Map && raw.containsKey('model')) {
                  final model = Map<String, dynamic>.from(raw['model'] as Map);
                  final number = model['number']?.toString() ?? '';
                  final ts = DateTime.parse(
                    model['timestamp'],
                  ).toUtc().toIso8601String();
                  final duration = model['duration']?.toString() ?? '';
                  final callType = model['call_type']?.toString() ?? '';
                  final composite = [number, ts, duration, callType].join('_');
                  if (existingSet.contains(composite)) {
                    // Mark as synced and remove from pending bucket
                    try {
                      StorageService.syncedBucket.put(key.toString(), nowIso);
                      StorageService.callBucket.delete(key);
                      removed++;
                      LoggerService.info('Removed duplicate local entry $key');
                    } catch (_) {}
                  }
                }
              } catch (e) {
                // ignore malformed
              }
            }
            LoggerService.info(
              'Deduplication completed, removed $removed duplicate(s)',
            );
          } catch (e) {
            LoggerService.warn('Deduplication step failed: $e');
          }

          // Now perform the normal background sync for remaining entries
          await CallLogService.performBackgroundSync();
        }

        await CallLogService.markFirstSyncCompleted();
        await CallLogService.updateLastSync('initial_sync');

        // Remove notification
        flutterLocalNotificationsPlugin.cancel(1001);

        LoggerService.info('Initial 3-day sync completed');
      } else {
        LoggerService.info('Initial sync already completed, skipping');
      }
    } catch (e, st) {
      LoggerService.error('Initial sync failed', e, st);
      // Remove notification on error
      flutterLocalNotificationsPlugin.cancel(1001);
    }

    // Note: Periodic sync is now handled by the call state listener
    // When a call ends, we schedule syncs at 3 minutes and 10 minutes
    // If another call starts during this window, the timers are cancelled

    // Also listen for stop command
    service.on('stop').listen((event) {
      LoggerService.info('BackgroundService received stop command');
      // Dispose call state listener before stopping
      callSvc.disposeCallStateListener();
      service.stopSelf();
    });
  }

  /// Show background notification
  static void _showBackgroundNotification(
    FlutterLocalNotificationsPlugin notificationsPlugin,
    String title,
    String content,
  ) {
    notificationsPlugin.show(
      1001,
      title,
      content,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'call_log_sync_channel',
          'Call Log Service',
          icon: 'ic_bg_service_small',
          ongoing: true,
          priority: Priority.high,
        ),
      ),
    );
  }
}
