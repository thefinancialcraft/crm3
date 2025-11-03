import 'package:logger/logger.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';
import 'storage_service.dart';
import '../utils/log_manager.dart' as lm;

class LoggerService {
  static final Logger _logger = Logger();
  static final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

  static void ui(String message) {
    _logger.i(message);
  // Mirror to LogManager as a UI event
  lm.log.logUI(message, level: lm.LogLevel.INFO);
    _forward(LogCategory.ui, message);
  }

  static void info(String message) {
    _logger.i(message);
  // Mirror to LogManager as a function info
  lm.log.info('LoggerService', message, isFunction: true);
    _forward(LogCategory.function, message);
  }

  static void warn(String message) {
    _logger.w(message);
  // Mirror to LogManager as a function warning
  lm.log.warning('LoggerService', message, isFunction: true);
    _forward(LogCategory.function, message);
  }

  static void error(String message, [Object? error, StackTrace? st]) {
    _logger.e(message, error: error, stackTrace: st);
    // Mirror to LogManager as a function error
    final full = '$message${error != null ? ' | $error' : ''}';
  lm.log.error('LoggerService', full, isFunction: true);
    _forward(LogCategory.function, full);
  }

  static void _forward(LogCategory category, String message) {
    final ctx = navKey.currentContext;
    if (ctx != null) {
      try {
        ctx.read<SyncProvider>().addLog(category, message);
        return;
      } catch (_) {
        // fallthrough to persist
      }
    }

    // If we cannot forward to the UI (for example when running in a background
    // isolate), persist the log so the UI can load it on startup.
    try {
      StorageService.appLogs.put(DateTime.now().toIso8601String(), {
        'category': category.index,
        'message': message,
      });
    } catch (_) {}
  }
}



