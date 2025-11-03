import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'logger_service.dart';

class PermissionService {
  static Future<void> requestEssential() async {
    // On web, many permissions are not supported, so we need to handle this gracefully
    if (kIsWeb) {
      LoggerService.info('Running on web - skipping platform-specific permissions');
      return;
    }

    // Request notification permission first
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final notificationStatus = await Permission.notification.request();
        LoggerService.info('Notification permission status: $notificationStatus');
      } catch (e) {
        LoggerService.warn('Notification permission request failed: $e');
      }
    }

    // Then request phone permission on Android
    if (Platform.isAndroid) {
      try {
        final phoneStatus = await Permission.phone.request();
        LoggerService.info('Phone permission status: $phoneStatus');
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
}