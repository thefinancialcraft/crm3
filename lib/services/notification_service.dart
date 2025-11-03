import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'logger_service.dart';

class NotificationService {
  static const channelId = 'call_log_sync_channel';
  static const channelName = 'Call Log Service';
  static const channelDescription = 'Shows notifications for call tracking and sync status';
  
  static FlutterLocalNotificationsPlugin? _plugin;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    final plugin = FlutterLocalNotificationsPlugin();
    
    // Create the notification channel for Android
    const channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.high,
    );

    // Initialize plugin with settings
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_bg_service_small'),
      ),
    );

    // Create the notification channel
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _plugin = plugin;
    _initialized = true;
    LoggerService.info('NotificationService initialized');
  }

  static Future<void> showCallActiveNotification() async {
    if (!_initialized) await initialize();
    
    await _plugin?.show(
      1001,
      'Call Active',
      'Call tracking is active',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          icon: 'ic_bg_service_small',
          ongoing: true,
          priority: Priority.high,
          showWhen: true,
        ),
      ),
    );
    LoggerService.info('Showed call active notification');
  }

  static Future<void> showCallEndedNotification() async {
    if (!_initialized) await initialize();
    
    await _plugin?.show(
      1001,
      'Call Ended',
      'Syncing call details...',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          icon: 'ic_bg_service_small',
          ongoing: true,
          priority: Priority.high,
          showWhen: true,
        ),
      ),
    );
    LoggerService.info('Showed call ended notification');
  }

  static Future<void> showSyncCompletedNotification(int callCount) async {
    if (!_initialized) await initialize();
    
    await _plugin?.show(
      1001,
      'Sync Complete',
      'Synced $callCount new call${callCount == 1 ? '' : 's'}',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          icon: 'ic_bg_service_small',
          priority: Priority.low,
          showWhen: true,
          autoCancel: true,
          onlyAlertOnce: true,
        ),
      ),
    );
    LoggerService.info('Showed sync completed notification');
  }

  static Future<void> showSyncErrorNotification(String error) async {
    if (!_initialized) await initialize();
    
    await _plugin?.show(
      1001,
      'Sync Error',
      'Failed to sync calls: $error',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          icon: 'ic_bg_service_small',
          priority: Priority.high,
          showWhen: true,
          autoCancel: true,
        ),
      ),
    );
    LoggerService.info('Showed sync error notification');
  }

  static Future<void> clearAllNotifications() async {
    await _plugin?.cancelAll();
    LoggerService.info('Cleared all notifications');
  }

  static Future<void> clearCallNotification() async {
    await _plugin?.cancel(1001);
    LoggerService.info('Cleared call notification');
  }
}