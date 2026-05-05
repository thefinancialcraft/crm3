import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'logger_service.dart';

class NotificationService {
  static const channelId = 'call_log_sync_channel';
  static const channelName = 'Call Log Service';
  static const channelDescription =
      'Shows notifications for call tracking and sync status';

  static const int _callNotifId   = 1001;  // Call related
  static const int _syncNotifId   = 1002;  // Sync complete
  static const int _errorNotifId  = 1003;  // Errors

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
    try {
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_launcher'),
        ),
      );
      LoggerService.info('NotificationService plugin initialized');
    } catch (e) {
      LoggerService.error('❌ Notification initialization failed', e);
      // Try again with a system default icon if ic_launcher fails
      try {
        await plugin.initialize(
          const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          ),
        );
        LoggerService.info('NotificationService initialized with @mipmap fallback');
      } catch (e2) {
        LoggerService.error('❌ Notification initialization failed even with fallback', e2);
      }
    }

    // Create the notification channel
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    _plugin = plugin;
    _initialized = true;
    LoggerService.info('NotificationService initialized');
  }

  static Future<void> showCallActiveNotification() async {
    if (!_initialized) await initialize();

    await _plugin?.show(
      _callNotifId,
      'Call Active',
      'Call tracking is active',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          icon: 'ic_launcher',
          ongoing: true,
          priority: Priority.high,
          showWhen: true,
        ),
      ),
    );
    LoggerService.info('Showed call active notification');
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await initialize();

    await _plugin?.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          icon: 'ic_launcher',
          priority: Priority.max,
          importance: Importance.max,
          showWhen: true,
        ),
      ),
    );
    LoggerService.info('Showed notification: $title - $body');
  }

  static Future<void> showCallNotification(String body) async {
    if (!_initialized) await initialize();

    await _plugin?.show(
      _callNotifId,
      'Call Detected',
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          icon: 'ic_launcher',
          ongoing: true,
          priority: Priority.high,
          showWhen: true,
        ),
      ),
    );
    LoggerService.info('Showed call notification: $body');
  }

  static Future<void> showCallEndedNotification() async {
    if (!_initialized) await initialize();

    await _plugin?.show(
      _callNotifId,
      'Call Ended',
      'Syncing call details...',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          icon: 'ic_launcher',
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
      _syncNotifId,
      'Sync Complete',
      'Synced $callCount new call${callCount == 1 ? '' : 's'}',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          icon: 'ic_launcher',
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
      _errorNotifId,
      'Sync Error',
      'Failed to sync calls: $error',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          icon: 'ic_launcher',
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
    await _plugin?.cancel(_callNotifId);
    LoggerService.info('Cleared call notification');
  }
}
