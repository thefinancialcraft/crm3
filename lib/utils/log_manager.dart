import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Log categories (broad grouping)
enum LogCategory { UI, FUNCTION }

/// Log levels for severity and color coding
enum LogLevel { INFO, SUCCESS, WARNING, ERROR }

class LogEntry {
  final LogCategory category;
  final LogLevel level;
  final String message;
  final DateTime time;
  final String? functionName;

  LogEntry({
    required this.category,
    required this.level,
    required this.message,
    DateTime? time,
    this.functionName,
  }) : time = time ?? DateTime.now();

  String get timeString {
    final t = time;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  }

  @override
  String toString() {
    if (category == LogCategory.UI) {
      return '[UI] $message | $timeString';
    } else {
      final fn = functionName ?? 'unknown';
      return '[FUNCTION: $fn] $message | $timeString';
    }
  }
}

/// A singleton LogManager that prints color-coded logs to the console,
/// keeps an in-memory buffer, exposes a stream for UI, and can export to a file.
class LogManager {
  LogManager._internal();

  static final LogManager _instance = LogManager._internal();

  factory LogManager() => _instance;

  final List<LogEntry> _buffer = [];
  final StreamController<LogEntry> _controller = StreamController.broadcast();

  /// Maximum cached entries in memory
  int maxEntries = 2000;

  Stream<LogEntry> get stream => _controller.stream;

  /// Add a UI log
  void logUI(String message, {LogLevel level = LogLevel.INFO}) {
    final entry = LogEntry(
      category: LogCategory.UI,
      level: level,
      message: message,
    );
    _add(entry);
  }

  /// Add a function log
  void logFunction(
    String functionName,
    String message, {
    LogLevel level = LogLevel.INFO,
  }) {
    final entry = LogEntry(
      category: LogCategory.FUNCTION,
      level: level,
      message: message,
      functionName: functionName,
    );
    _add(entry);
  }

  /// Convenience wrappers
  void info(String tagOrFn, String message, {bool isFunction = false}) {
    if (isFunction) {
      logFunction(tagOrFn, message, level: LogLevel.INFO);
    } else {
      logUI(message, level: LogLevel.INFO);
    }
  }

  void success(String tagOrFn, String message, {bool isFunction = false}) {
    if (isFunction) {
      logFunction(tagOrFn, message, level: LogLevel.SUCCESS);
    } else {
      logUI(message, level: LogLevel.SUCCESS);
    }
  }

  void warning(String tagOrFn, String message, {bool isFunction = false}) {
    if (isFunction) {
      logFunction(tagOrFn, message, level: LogLevel.WARNING);
    } else {
      logUI(message, level: LogLevel.WARNING);
    }
  }

  void error(String tagOrFn, String message, {bool isFunction = false}) {
    if (isFunction) {
      logFunction(tagOrFn, message, level: LogLevel.ERROR);
    } else {
      logUI(message, level: LogLevel.ERROR);
    }
  }

  void _add(LogEntry entry) {
    // add to buffer
    _buffer.add(entry);
    if (_buffer.length > maxEntries) {
      _buffer.removeRange(0, _buffer.length - maxEntries);
    }

    // push to stream
    try {
      _controller.add(entry);
    } catch (_) {}

    // print to console with color
    _printColored(entry);
  }

  List<LogEntry> getLogs({
    List<LogCategory>? categories,
    List<LogLevel>? levels,
  }) {
    return _buffer
        .where((e) {
          final catOk = categories == null || categories.contains(e.category);
          final levelOk = levels == null || levels.contains(e.level);
          return catOk && levelOk;
        })
        .toList(growable: false);
  }

  void clear() {
    _buffer.clear();
    // also notify listeners with a special UI message
    _controller.add(
      LogEntry(
        category: LogCategory.UI,
        level: LogLevel.INFO,
        message: 'Logs cleared',
      ),
    );
  }

  Future<File> saveToFile({String? filename, bool share = false}) async {
    // Use temporary directory (doesn't require permissions on Android 10+)
    final dir = await getTemporaryDirectory();
    final name =
        filename ??
        'logs_${DateTime.now().toIso8601String().replaceAll(':', '-')}.txt';
    final file = File('${dir.path}/$name');
    final sink = file.openWrite(mode: FileMode.write);
    for (final e in _buffer) {
      sink.writeln(e.toString());
    }
    await sink.flush();
    await sink.close();
    info('LogManager', 'Logs saved to ${file.path}', isFunction: true);

    // Share file if requested (no permissions needed)
    if (share) {
      try {
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Logs export',
          subject: 'CRM3 Logs',
        );
      } catch (e) {
        warning('LogManager', 'Failed to share logs: $e', isFunction: true);
      }
    }

    return file;
  }

  void _printColored(LogEntry e) {
    final reset = '\x1B[0m';
    final color = _colorForEntry(e);
    final text = e.toString();

    // Use debugPrint on flutter to avoid truncation in some consoles
    final colored = '$color$text$reset';
    if (kDebugMode) {
      debugPrint(colored);
    } else {
      print(text); // avoid ANSI output in release
    }
  }

  String _colorForEntry(LogEntry e) {
    // ANSI colors
    // INFO / UI -> cyan, SUCCESS -> green, WARNING -> yellow, ERROR -> red
    switch (e.level) {
      case LogLevel.SUCCESS:
        return '\x1B[32m';
      case LogLevel.WARNING:
        return '\x1B[33m';
      case LogLevel.ERROR:
        return '\x1B[31m';
      case LogLevel.INFO:
        if (e.category == LogCategory.UI) return '\x1B[36m';
        return '\x1B[34m';
    }
  }

  /// Dispose the stream controller when app closes (not strictly necessary for singleton)
  void dispose() {
    try {
      _controller.close();
    } catch (_) {}
  }
}

// Convenience top-level accessor
final log = LogManager();
