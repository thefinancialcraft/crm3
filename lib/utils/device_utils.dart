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
  static Future<Map<String, dynamic>> getDeviceInfo() async {
    final Map<String, dynamic> out = {
      'deviceId': 'unknown',
      'osVersion': 'unknown',
      'device': 'unknown',
      'model': 'unknown',
      'brand': 'unknown',
      'sdkVersion': 'unknown',
      'androidId': 'unknown',
      'manufacturer': 'unknown',
      'board': 'unknown',
      'hardware': 'unknown',
      'product': 'unknown',
      'isPhysicalDevice': true,
    };

    if (kIsWeb) {
      out['deviceId'] = 'web-unknown';
      out['osVersion'] = 'Web';
      out['device'] = 'Web Browser';
      out['model'] = 'Web';
      out['brand'] = 'Web';
      out['sdkVersion'] = 'N/A';
      out['androidId'] = 'N/A';
      out['isPhysicalDevice'] = false;
      LoggerService.info('DeviceUtils.getDeviceInfo -> web');
      return out;
    }

    final info = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        out['deviceId'] = a.id;
        out['osVersion'] = a.version.release;
        out['device'] = a.device;
        out['model'] = a.model;
        out['brand'] = a.brand;
        out['sdkVersion'] = a.version.sdkInt.toString();
        out['androidId'] = a.id;
        out['manufacturer'] = a.manufacturer;
        out['board'] = a.board;
        out['hardware'] = a.hardware;
        out['product'] = a.product;
        out['isPhysicalDevice'] = a.isPhysicalDevice;
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        out['deviceId'] = i.identifierForVendor ?? out['deviceId']!;
        out['osVersion'] = '${i.systemName} ${i.systemVersion}';
        out['device'] = i.name;
        out['model'] = i.utsname.machine;
        out['brand'] = 'Apple';
        out['sdkVersion'] = 'N/A';
        out['androidId'] = 'N/A';
        out['isPhysicalDevice'] = i.isPhysicalDevice;
      }
    } catch (e) {
      LoggerService.warn('getDeviceInfo failed: $e');
    }
    return out;
  }
}
