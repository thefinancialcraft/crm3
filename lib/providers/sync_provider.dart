import 'package:flutter/foundation.dart';
import '../services/storage_service.dart';
import '../models/user_model.dart';
import '../services/logger_service.dart';

enum LogCategory { ui, function }

enum LogLevel { info, success, warning, error }

class LogEntry {
  final DateTime timestamp;
  final LogCategory category;
  final LogLevel level;
  final String tag; // optional small tag like FUNCTION: connectToSupabase or UI
  final String message;

  LogEntry(
    this.category,
    this.message, {
    this.level = LogLevel.info,
    this.tag = '',
  }) : timestamp = DateTime.now();

  Map<String, Object?> toMap() => {
    'timestamp': timestamp.toIso8601String(),
    'category': LogCategory.values.indexOf(category),
    'level': LogLevel.values.indexOf(level),
    'tag': tag,
    'message': message,
  };

  static LogEntry fromMap(Map v) {
    final idx = v['category'] is int ? v['category'] as int : 0;
    final cat = LogCategory.values[idx.clamp(0, LogCategory.values.length - 1)];
    final lvlIdx = v['level'] is int ? v['level'] as int : 0;
    final lvl = LogLevel.values[lvlIdx.clamp(0, LogLevel.values.length - 1)];
    final msg = v['message']?.toString() ?? '';
    final tag = v['tag']?.toString() ?? '';
    final entry = LogEntry(cat, msg, level: lvl, tag: tag);
    try {
      if (v['timestamp'] is String) {
        entry.timestamp;
      }
    } catch (_) {}
    return entry;
  }
}

class SyncProvider extends ChangeNotifier {
  SyncProvider() {
    _loadPersistedLogs();
    _loadCountsAndLastSync();
    _loadUser();
    _loadSessions();
  }
  bool _isSyncing = false;
  UserModel? _user;
  List<Map<String, dynamic>> _pastSessions = [];
  int _pending = 0;
  int _synced = 0;
  DateTime? _lastSync;
  String? _deviceId;
  final List<LogEntry> _logs = <LogEntry>[];
  LogCategory? _activeFilter = LogCategory.function;
  LogLevel? _activeLevelFilter;
  final List<String> _webViewMessagesIn = <String>[];
  final List<String> _webViewMessagesOut = <String>[];

  bool get isSyncing => _isSyncing;
  int get pending => _pending;
  int get synced => _synced;
  DateTime? get lastSync => _lastSync;
  String? get deviceId => _deviceId;
  UserModel? get user => _user;
  List<Map<String, dynamic>> get pastSessions =>
      List.unmodifiable(_pastSessions);
  LogCategory? get activeFilter => _activeFilter;
  LogLevel? get activeLevelFilter => _activeLevelFilter;
  List<LogEntry> get allLogs => List.unmodifiable(_logs);
  List<String> get webViewMessagesIn => List.unmodifiable(_webViewMessagesIn);
  List<String> get webViewMessagesOut => List.unmodifiable(_webViewMessagesOut);

  List<LogEntry> get filteredLogs {
    return _logs
        .where((e) {
          final catOk = _activeFilter == null
              ? true
              : e.category == _activeFilter;
          final lvlOk = _activeLevelFilter == null
              ? true
              : e.level == _activeLevelFilter;
          return catOk && lvlOk;
        })
        .toList(growable: false);
  }

  void setSyncing(bool value) {
    _isSyncing = value;
    notifyListeners();
  }

  void setCounts({required int pending, required int synced}) {
    _pending = pending;
    _synced = synced;
    notifyListeners();
  }

  void setLastSync(DateTime t) {
    _lastSync = t;
    notifyListeners();
  }

  void setDeviceId(String id) {
    _deviceId = id;
    notifyListeners();
  }

  void updateUser(UserModel u) {
    LoggerService.info("🔄 SyncProvider: Updating user to ${u.userName}");
    if (_user != null && _user!.employeeId != u.employeeId) {
      final archived = {
        'id': _user!.employeeId,
        'name': _user!.userName,
        'firstLogin': _user!.createdAt,
        'lastLogin': _user!.lastSignInAt,
        'lastLogout': DateTime.now().toIso8601String(),
        'role': _user!.role,
      };
      _pastSessions.insert(0, archived);
      StorageService.saveUserSessions(_pastSessions);
    }
    _user = u;
    StorageService.setUser(u.toJson());
    notifyListeners();
  }

  void setFilter(LogCategory? c) {
    _activeFilter = c;
    notifyListeners();
  }

  void setLevelFilter(LogLevel? l) {
    _activeLevelFilter = l;
    notifyListeners();
  }

  void addLog(
    LogCategory category,
    String message, {
    LogLevel level = LogLevel.info,
    String tag = '',
  }) {
    final entry = LogEntry(category, message, level: level, tag: tag);
    _logs.add(entry);
    // persist to Hive for short-term retrieval across restarts
    try {
      final box = StorageService.appLogs;
      box.put(entry.timestamp.toIso8601String(), entry.toMap());
    } catch (_) {}
    notifyListeners();
  }

  void _loadPersistedLogs() {
    try {
      final box = StorageService.appLogs;
      final keys = box.keys.toList();
      for (final k in keys) {
        final v = box.get(k);
        if (v is Map) {
          try {
            final entry = LogEntry.fromMap(v);
            _logs.add(entry);
          } catch (_) {
            // fallback: older shape
            final idx = v['category'] is int ? v['category'] as int : 0;
            final cat =
                LogCategory.values[idx.clamp(0, LogCategory.values.length - 1)];
            final msg = v['message']?.toString() ?? '';
            _logs.add(LogEntry(cat, msg));
          }
        }
      }
      if (keys.isNotEmpty) {
        box.clear();
        notifyListeners();
      }
    } catch (_) {}
  }

  void clearLogs() {
    _logs.clear();
    try {
      StorageService.appLogs.clear();
    } catch (_) {}
    notifyListeners();
  }

  void addWebViewMessageIn(String message) {
    if (_webViewMessagesIn.length >= 100) {
      _webViewMessagesIn.removeAt(0);
    }
    _webViewMessagesIn.add('${DateTime.now().toIso8601String()}: $message');
    notifyListeners();
  }

  void addWebViewMessageOut(String message) {
    if (_webViewMessagesOut.length >= 100) {
      _webViewMessagesOut.removeAt(0);
    }
    _webViewMessagesOut.add('${DateTime.now().toIso8601String()}: $message');
    notifyListeners();
  }

  void clearWebViewMessages() {
    _webViewMessagesIn.clear();
    _webViewMessagesOut.clear();
    notifyListeners();
  }

  /// Load counts and last sync from storage on app start
  void _loadCountsAndLastSync() {
    try {
      // Load pending and synced counts from storage
      final pendingCount = StorageService.callBucket.length;
      final syncedCount = StorageService.syncedBucket.length;
      _pending = pendingCount;
      _synced = syncedCount;

      // Load last sync timestamp from storage
      final lastSyncFromStorage = StorageService.getLastSync();
      if (lastSyncFromStorage != null) {
        _lastSync = lastSyncFromStorage;
      }

      notifyListeners();
    } catch (_) {
      // If storage not ready yet, counts remain 0
      // They'll be updated by the timer in DevModePage or when sync happens
    }
  }

  void _loadUser() {
    final map = StorageService.getUser();
    if (map != null) {
      try {
        _user = UserModel.fromJson(map);
        notifyListeners();
      } catch (_) {}
    }
  }

  void _loadSessions() {
    _pastSessions = StorageService.getUserSessions();
    notifyListeners();
  }
}
