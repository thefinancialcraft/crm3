import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'logger_service.dart';

class PermissionService {
  static Future<void> requestEssential() async {
    if (kIsWeb) return;

    // 1. Notifications
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await Permission.notification.request();
      } catch (e) {
        LoggerService.error('Notification permission failed', e);
      }
    }

    // 2. Phone permissions
    if (Platform.isAndroid) {
      try {
        await Permission.phone.request();
      } catch (e) {
        LoggerService.error('Phone permission failed', e);
      }

      // READ_CALL_LOG — Android 9+ (API 28+) pe alag permission hai
      try {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt >= 28) {
          // permission_handler mein phone permission call log bhi cover karti hai 
          // agar manifest mein declared ho.
          await Permission.phone.request();
          LoggerService.info('READ_CALL_LOG requested for API ${androidInfo.version.sdkInt}');
        }
      } catch (e) {
        LoggerService.error('READ_CALL_LOG permission failed', e);
      }
    }

    // 3. Contacts
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await Permission.contacts.request();
      } catch (e) {
        LoggerService.error('Contacts permission failed', e);
      }
    }

    // 4. Overlay + Battery
    if (Platform.isAndroid) {
      try {
        await Permission.systemAlertWindow.request();
        await Permission.ignoreBatteryOptimizations.request();
      } catch (e) {
        LoggerService.error('Overlay/Battery permission failed', e);
      }
    }
  }

  /// Check which essential permissions are missing (denied or permanently denied)
  /// Returns a list of user-friendly names for missing permissions.
  static Future<List<String>> checkMissingPermissions() async {
    if (kIsWeb) return [];

    final missing = <String>[];

    if (Platform.isAndroid || Platform.isIOS) {
      if (!await Permission.notification.isGranted) {
        missing.add('Notifications');
      }
      if (!await Permission.contacts.isGranted) {
        missing.add('Contacts');
      }
    }

    if (Platform.isAndroid) {
      if (!await Permission.phone.isGranted) {
        missing.add('Phone (Manage Calls)');
      }
      /* 
      // Overlay is now optional as per user request
      if (!await Permission.systemAlertWindow.isGranted) {
        missing.add('Display Over Apps');
      }
      */
    }

    return missing;
  }
}
