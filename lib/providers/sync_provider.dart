import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../services/storage_service.dart';
import '../models/user_model.dart';
import '../services/logger_service.dart';
import '../utils/log_manager.dart' as lm;

class LogEntry {
  final DateTime timestamp;
  final lm.LogCategory category;
  final lm.LogLevel level;
  final String tag; // optional small tag like FUNCTION: connectToSupabase or UI
  final String message;

  LogEntry(
    this.category,
    this.message, {
    this.level = lm.LogLevel.info,
    this.tag = '',
  }) : timestamp = DateTime.now();

  Map<String, Object?> toMap() => {
    'timestamp': timestamp.toIso8601String(),
    'category': lm.LogCategory.values.indexOf(category),
    'level': lm.LogLevel.values.indexOf(level),
    'tag': tag,
    'message': message,
  };

  static LogEntry fromMap(Map v) {
    final idx = v['category'] is int ? v['category'] as int : 0;
    final cat = lm.LogCategory.values[idx.clamp(0, lm.LogCategory.values.length - 1)];
    final lvlIdx = v['level'] is int ? v['level'] as int : 0;
    final lvl = lm.LogLevel.values[lvlIdx.clamp(0, lm.LogLevel.values.length - 1)];
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
    loadSimPreference();
    refreshSims();

    // Listen to real-time logs from LogManager
    lm.LogManager().stream.listen((log) {
      addLog(
          log.category,
          log.message,
          level: log.level,
          tag: log.functionName ?? '');
    });

    // Start a periodic timer to pull counts and SIM status (less frequent)
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      refreshCounts();
      refreshPersistedLogs();
      // Periodically refresh SIMs in case they changed at OS level
      refreshSims();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
  bool _isSyncing = false;
  UserModel? _user;
  List<Map<String, dynamic>> _pastSessions = [];
  int _pending = 0;
  int _synced = 0;
  DateTime? _lastSync;
  String? _deviceId;
  final List<LogEntry> _logs = <LogEntry>[];
  lm.LogCategory? _activeFilter = lm.LogCategory.function;
  lm.LogLevel? _activeLevelFilter;
  final List<String> _webViewMessagesIn = <String>[];
  final List<String> _webViewMessagesOut = <String>[];
  bool _showLiveLogs = true;
  List<Map<String, dynamic>> _availableSims = [];
  String? _defaultSimId;

  // Polling timer for real-time updates
  Timer? _refreshTimer;

  bool get isSyncing => _isSyncing;
  bool get showLiveLogs => _showLiveLogs;
  int get pending => _pending;
  int get synced => _synced;
  DateTime? get lastSync => _lastSync;
  String? get deviceId => _deviceId;
  UserModel? get user => _user;
  List<Map<String, dynamic>> get pastSessions =>
      List.unmodifiable(_pastSessions);
  lm.LogCategory? get activeFilter => _activeFilter;
  lm.LogLevel? get activeLevelFilter => _activeLevelFilter;
  List<LogEntry> get allLogs => List.unmodifiable(_logs);
  List<String> get webViewMessagesIn => List.unmodifiable(_webViewMessagesIn);
  List<String> get webViewMessagesOut => List.unmodifiable(_webViewMessagesOut);
  List<Map<String, dynamic>> get availableSims => _availableSims;
  String? get defaultSimId => _defaultSimId;

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

  void setFilter(lm.LogCategory? c) {
    LoggerService.info("SyncProvider: Setting filter to $c");
    _activeFilter = c;
    notifyListeners();
  }

  void setShowLiveLogs(bool value) {
    LoggerService.info("SyncProvider: Setting showLiveLogs to $value");
    _showLiveLogs = value;
    notifyListeners();
  }

  void setLevelFilter(lm.LogLevel? l) {
    _activeLevelFilter = l;
    notifyListeners();
  }

  void addLog(
    lm.LogCategory category,
    String message, {
    lm.LogLevel level = lm.LogLevel.info,
    String tag = '',
  }) {
    final entry = LogEntry(category, message, level: level, tag: tag);
    _logs.add(entry);
    // Limit in-memory logs
    if (_logs.length > 1000) {
      _logs.removeRange(0, _logs.length - 1000);
    }
    notifyListeners();
  }

  /// Load SIM Preference
  void loadSimPreference() {
    _defaultSimId = StorageService.getDefaultSim();
    notifyListeners();
  }

  /// Update Default SIM
  Future<void> setDefaultSim(String? simId) async {
    LoggerService.info("📱 SyncProvider: Setting default SIM to $simId (Previous: $_defaultSimId)");
    _defaultSimId = simId;
    await StorageService.setDefaultSim(simId);
    notifyListeners();
  }

  /// Refresh available SIMs from native
  Future<void> refreshSims() async {
    const channel = MethodChannel('com.example.crm3/overlay');
    try {
      final List? sims = await channel.invokeMethod('getSimCards');
      if (sims != null) {
        _availableSims = sims.map((e) => Map<String, dynamic>.from(e)).toList();
        notifyListeners();
      }
    } catch (e) {
      LoggerService.error("❌ Failed to fetch SIM cards", e);
    }
  }

  /// Pulls logs from Hive that might have been written by background services
  void refreshPersistedLogs() {
    try {
      final box = StorageService.appLogs;
      if (box.isEmpty) return;

      final keys = box.keys.toList();
      bool added = false;
      for (final k in keys) {
        final v = box.get(k);
        if (v is Map) {
          try {
            final entry = LogEntry.fromMap(v);
            _logs.add(entry);
            added = true;
          } catch (_) {}
        }
      }
      if (added) {
        box.clear();
        notifyListeners();
      }
    } catch (_) {}
  }

  void _loadPersistedLogs() {
    refreshPersistedLogs();
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

  /// Refresh counts and last sync from storage (used for live updates)
  void refreshCounts() {
    try {
      final pendingCount = StorageService.callBucket.length;
      final syncedCount = StorageService.syncedBucket.length;
      final lastSyncFromStorage = StorageService.getLastSync();

      bool changed = false;

      if (pendingCount != _pending) {
        _pending = pendingCount;
        changed = true;
      }
      if (syncedCount != _synced) {
        _synced = syncedCount;
        changed = true;
      }
      if (lastSyncFromStorage != null &&
          (_lastSync == null ||
              lastSyncFromStorage.difference(_lastSync!).inSeconds.abs() > 0)) {
        _lastSync = lastSyncFromStorage;
        changed = true;
      }

      if (changed) {
        notifyListeners();
      }
    } catch (_) {}
  }

  void _loadCountsAndLastSync() {
    refreshCounts();
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
