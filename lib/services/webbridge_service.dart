import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'call_log_service.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'logger_service.dart';
import 'sync_service.dart';
import '../models/user_model.dart';
import '../providers/sync_provider.dart';
import '../pages/dev_mode_page.dart';
import '../utils/device_utils.dart';

class WebBridgeService {
  static InAppWebViewController? _controller;
  static bool callAlive = false;

  /// Bridge connection status
  static bool get isConnected => _controller != null;

  // =========================
  // 🚀 INITIALIZE BRIDGE
  // =========================

  static void init(InAppWebViewController controller) {
    _controller = controller;

    LoggerService.info("🔗 WebBridge initialized");

    // Register both names to ensure compatibility
    for (final handler in ['bridge', 'fromWebApp']) {
      controller.addJavaScriptHandler(
        handlerName: handler,
        callback: (args) async {
          if (args.isEmpty) return;

          dynamic raw = args.first;
          Map<String, dynamic> data;

          try {
            if (raw is String) {
              data = Map<String, dynamic>.from(jsonDecode(raw));
            } else if (raw is Map) {
              data = Map<String, dynamic>.from(raw);
            } else {
              throw Exception(
                "Payload is neither Map nor String: ${raw.runtimeType}",
              );
            }
          } catch (e) {
            LoggerService.warn(
              "⚠️ Bridge parse error ($handler): $e | Raw: $raw",
            );
            return;
          }

          final type = (data['type'] ?? data['Type'] ?? data['event'])
              ?.toString()
              .trim()
              .toLowerCase();

          final value = data['value'] ?? data['Value'];

          if (type == null || type.isEmpty) {
            LoggerService.warn("⚠️ Missing event type in $handler payload");
            return;
          }

          LoggerService.info("📥 [Web → Flutter] $type | ${jsonEncode(value)}");
          _logIn("📥 $type → ${jsonEncode(value)}");

          switch (type) {
            case 'isdevmode_open':
            case 'open_dev_mode':
              _handleOpenDevMode(value);
              break;

            case 'login':
              _ack('login_ack', true);
              LoggerService.info("🚀 WebBridge: Handling login event");
              try {
                await CallLogService().onUserLogin();
                await SyncService(
                  Supabase.instance.client,
                ).updateSyncMeta(isLogin: true);
              } catch (e) {
                LoggerService.error("❌ Failed to update sync_meta on login", e);
              }
              break;

            case 'logout':
              _ack('logout_ack', true);
              LoggerService.info("🚀 WebBridge: Handling logout event");
              try {
                await CallLogService().onUserLogout();
                await SyncService(
                  Supabase.instance.client,
                ).updateSyncMeta(isLogin: false);
              } catch (e) {
                LoggerService.error(
                  "❌ Failed to update sync_meta on logout",
                  e,
                );
              }
              break;

            case 'sync_user_info':
              await _handleSyncUserInfo(value);
              break;

            case 'request':
              if (value == 'device_info') {
                final deviceInfo = await DeviceUtils.getDeviceInfo();
                _ack('device_info', deviceInfo);
              }
              break;
            case 'call_disconnect':
              if (value != null) {
                LoggerService.info(
                  "📞 WebBridge: Requesting call disconnect for $value",
                );
                callAlive = false;
                await CallLogService().disconnectCall();
                _ack('call_disconnect_ack', true);
              } else {
                _ack('call_disconnect_ack', false);
              }
              break;

            case 'call_to':
              if (value != null) {
                LoggerService.info(
                  "📞 WebBridge: Placing direct call to $value",
                );
                callAlive = true;
                await CallLogService().placeDirectCall(value.toString());
                _ack('call_to_ack', true);
              } else {
                _ack('call_to_ack', false);
              }
              break;

            default:
              LoggerService.warn("⚠️ No event: $type");
              _ack('no_event', type);
          }
        },
      );
    }
  }

  // =========================
  // 🔧 EVENT HANDLERS
  // =========================

  static void _handleOpenDevMode(dynamic value) {
    if (value == true) {
      final nav = LoggerService.navKey.currentState;
      if (nav != null) {
        nav.push(MaterialPageRoute(builder: (_) => const DevModePage()));
        _ack('open_dev_mode_ack', true);
      }
    } else {
      _ack('open_dev_mode_ack', false);
    }
  }

  static Future<void> _handleSyncUserInfo(dynamic value) async {
    try {
      LoggerService.info("🔄 Processing user sync...");
      LoggerService.ui("🔄 Syncing user info...");

      Map<String, dynamic> userMap;
      if (value is Map) {
        userMap = Map<String, dynamic>.from(value);
      } else if (value is String) {
        userMap = Map<String, dynamic>.from(jsonDecode(value));
      } else {
        throw Exception("Invalid user payload type: ${value.runtimeType}");
      }

      final user = UserModel.fromJson(userMap);
      LoggerService.info(
        "👤 Parsed User: ${user.userName} (${user.employeeId})",
      );

      final ctx = LoggerService.navKey.currentContext;
      if (ctx == null) {
        throw Exception("No BuildContext found");
      }

      ctx.read<SyncProvider>().updateUser(user);

      // Update sync_meta in Supabase immediately after login/sync
      LoggerService.info("🚀 WebBridge: Syncing user info metadata");
      try {
        await SyncService(
          Supabase.instance.client,
        ).updateSyncMeta(isLogin: true);
        await CallLogService().onUserLogin();
      } catch (e) {
        LoggerService.warn("⚠️ Failed to update sync_meta on user sync: $e");
      }

      LoggerService.info("✅ User synced successfully: ${user.userName}");
      LoggerService.ui("✅ User info updated: ${user.userName}");

      _ack('sync_user_info_ack', true);
    } catch (e, st) {
      LoggerService.error("❌ User sync failed", e, st);
      LoggerService.ui("❌ User sync failed: $e");
      _ack('sync_user_info_error', e.toString());
    }
  }

  // =========================
  // 📤 FLUTTER → WEB
  // =========================

  static Future<void> sendToWeb(String type, dynamic value) async {
    if (_controller == null) return;

    final payload = {
      'type': type,
      'value': value,
      'meta': {
        'source': 'flutter',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    };

    final js =
        "window.fromFlutter && window.fromFlutter(${jsonEncode(payload)});";

    await _controller!.evaluateJavascript(source: js);

    LoggerService.info("📤 [Flutter → Web] $type");
    _logOut("📤 $type → ${jsonEncode(value)}");
  }

  static void notifyCallEnded([String? number]) {
    callAlive = false;
    sendToWeb('call_disconected', number);
  }

  static void _ack(String type, dynamic value) {
    sendToWeb(type, value);
  }

  // =========================
  // 🧾 LOG HELPERS
  // =========================

  static void _logIn(String message) {
    final ctx = LoggerService.navKey.currentContext;
    if (ctx != null) {
      ctx.read<SyncProvider>().addWebViewMessageIn(message);
    }
  }

  static void _logOut(String message) {
    final ctx = LoggerService.navKey.currentContext;
    if (ctx != null) {
      ctx.read<SyncProvider>().addWebViewMessageOut(message);
    }
  }
}
