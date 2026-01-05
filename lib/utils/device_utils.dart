import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/logger_service.dart';

class DeviceUtils {
  /// Returns a stable device id (best-effort) and logs it.
  static Future<String> getDeviceId() async {
    if (kIsWeb) {
      LoggerService.info('DeviceUtils.getDeviceId -> web-unknown');
      return 'web-unknown';
    }

    final info = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        LoggerService.info('DeviceUtils.getDeviceId -> ${android.id}');
        return android.id;
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        return ios.identifierForVendor ?? 'ios-unknown';
      }
    } catch (e) {
      LoggerService.warn('getDeviceId failed: $e');
    }
    return 'unknown-device';
  }

  /// Returns a map of useful device info fields (id, osVersion, name, model)
  static Future<Map<String, String>> getDeviceInfo() async {
    final Map<String, String> out = {
      'deviceId': 'unknown',
      'osVersion': 'unknown',
      'deviceName': 'unknown',
      'model': 'unknown',
      'brand': 'unknown',
      'sdkVersion': 'unknown',
      'androidId': 'unknown',
    };

    if (kIsWeb) {
      out['deviceId'] = 'web-unknown';
      out['osVersion'] = 'Web';
      out['deviceName'] = 'Web Browser';
      out['model'] = 'Web';
      out['brand'] = 'Web';
      out['sdkVersion'] = 'N/A';
      out['androidId'] = 'N/A';
      LoggerService.info('DeviceUtils.getDeviceInfo -> web');
      return out;
    }

    final info = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        out['deviceId'] = a.id;
        out['osVersion'] = a.version.release;
        out['deviceName'] = a.device;
        out['model'] = a.model;
        out['brand'] = a.brand;
        out['sdkVersion'] = a.version.sdkInt.toString();
        out['androidId'] = a
            .id; // androidInfo.id IS the android_id usually, or similar unique ID
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        out['deviceId'] = i.identifierForVendor ?? out['deviceId']!;
        out['osVersion'] = '${i.systemName} ${i.systemVersion}';
        out['deviceName'] = i.name;
        out['model'] = i.utsname.machine;
        out['brand'] = 'Apple';
        out['sdkVersion'] = 'N/A';
        out['androidId'] = 'N/A';
      }
    } catch (e) {
      LoggerService.warn('getDeviceInfo failed: $e');
    }
    return out;
  }
}
