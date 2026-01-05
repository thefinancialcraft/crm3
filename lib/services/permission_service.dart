import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'logger_service.dart';

class PermissionService {
  static Future<void> requestEssential() async {
    // On web, many permissions are not supported, so we need to handle this gracefully
    if (kIsWeb) {
      LoggerService.info(
        'Running on web - skipping platform-specific permissions',
      );
      return;
    }

    // Request notification permission first
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final notificationStatus = await Permission.notification.request();
        LoggerService.info(
          'Notification permission status: $notificationStatus',
        );
      } catch (e) {
        LoggerService.warn('Notification permission request failed: $e');
      }
    }

    // Then request phone permission on Android
    if (Platform.isAndroid) {
      try {
        final phoneStatus = await Permission.phone.request();
        LoggerService.info('Phone permission status: $phoneStatus');

        // Also request call logs permission explicitly if needed for newer Android
        // though strictly 'phone' covers core features, sometimes logs are separate.
        // For now sticking to phone as per existing code.
      } catch (e) {
        LoggerService.warn('Phone permission request failed: $e');
      }
    }

    // Finally request contacts permission
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final contactsStatus = await Permission.contacts.request();
        LoggerService.info('Contacts permission status: $contactsStatus');
      } catch (e) {
        LoggerService.warn('Contacts permission request failed: $e');
      }
    }
    // Request System Alert Window permission for overlay
    if (Platform.isAndroid) {
      try {
        final overlayStatus = await Permission.systemAlertWindow.request();
        LoggerService.info('Overlay permission status: $overlayStatus');

        final batteryStatus = await Permission.ignoreBatteryOptimizations
            .request();
        LoggerService.info('Battery optimization status: $batteryStatus');
      } catch (e) {
        LoggerService.warn('Overlay/Battery permission request failed: $e');
      }
    }

    // Double check phone permission on Android
    if (Platform.isAndroid && await Permission.phone.isDenied) {
      LoggerService.warn('Phone permission still denied; requesting again');
      try {
        await Permission.phone.request();
      } catch (e) {
        LoggerService.warn('Phone permission request failed: $e');
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
      if (!await Permission.systemAlertWindow.isGranted) {
        missing.add('Display Over Apps');
      }
    }

    return missing;
  }
}
