import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart'; 
import 'logger_service.dart';
import 'storage_service.dart';

/// ---------------------------------------------------------------------------
///  UpdateService (Manual Distribution Version)
///  Optimized for Rynxly CRM with Premium UI
/// ---------------------------------------------------------------------------

class UpdateService with WidgetsBindingObserver {
  UpdateService._() {
    WidgetsBinding.instance.addObserver(this);
  }
  static final UpdateService instance = UpdateService._();

  static const String _versionUrl = 'https://www.rynxly.in/app/version.json'; 
  static String? _downloadedApkPath;
  static bool _isDownloadingSilently = false;

  // 🛡️ PENDING STATE: To resume flow after settings redirect
  String? _pendingVersion;
  String? _pendingNotes;
  String? _pendingApkUrl;
  bool _isWaitingForPermission = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isWaitingForPermission) {
      _isWaitingForPermission = false;
      _handlePermissionResume();
    }
  }

  Future<void> _handlePermissionResume() async {
    // 🛡️ Settle delay: Give Android time to switch back to Flutter view
    await Future.delayed(const Duration(milliseconds: 600));

    final channel = const MethodChannel('com.example.crm3/main');
    final bool hasPermission = await channel.invokeMethod('checkInstallPermission') ?? false;
    
    // 🛡️ Show dialog on resume if we have a pending APK, regardless of permission status.
    // This gives the user a UI to interact with (either try again or dismiss).
    if (_downloadedApkPath != null) {
      LoggerService.info("🚀 Update: Resuming update flow. Permission: $hasPermission");
      final context = LoggerService.navKey.currentContext;
      if (context != null && context.mounted) {
        _showUpdateDialog(
          context, 
          version: _pendingVersion ?? "New", 
          notes: _pendingNotes ?? "", 
          apkUrl: _pendingApkUrl ?? "", 
          isReady: true
        );
        
        // Only clear pending state if permission is granted, otherwise keep it for next resume
        if (hasPermission) {
          _pendingVersion = null;
          _pendingNotes = null;
          _pendingApkUrl = null;
        }
      }
    }
  }

  Future<void> checkForUpdate(BuildContext context, {bool silent = false}) async {
    try {
      if (_isDownloadingSilently) {
        LoggerService.info("🚀 Update: A background download is already in progress.");
        return;
      }

      LoggerService.info("🚀 Update: Checking for updates...");
      
      final remote = await _fetchRemoteVersion();
      if (remote == null) return;

      final bool isForceUpdate = remote['force_update'] ?? false;
      final info = await PackageInfo.fromPlatform();
      
      final int remoteCode = remote['version_code'] ?? 0;
      final int localCode = int.tryParse(info.buildNumber) ?? 0;
      
      final String remoteName = remote['version'] ?? '0.0.0';
      final String localName = info.version;

      bool updateAvailable = false;
      
      if (remoteCode > 0 && localCode > 0) {
        updateAvailable = remoteCode > localCode;
      } else {
        final localParts = _parseVersion(localName);
        final latestParts = _parseVersion(remoteName);
        updateAvailable = _isNewer(latestParts, localParts);
      }

      if (updateAvailable) {
        final apkUrl = remote['url'] ?? 'https://www.rynxly.in/app/rynxly.apk';

        // Check if we already have it downloaded
        if (_downloadedApkPath != null && File(_downloadedApkPath!).existsSync()) {
          LoggerService.info("🚀 Update: New version already downloaded. Ready to install.");
          if (!context.mounted) return;
          _showUpdateDialog(context, version: remoteName, notes: remote['changelog'] ?? '', apkUrl: apkUrl, isReady: true);
          return;
        }

        if (silent && !isForceUpdate) {
          // Check dismissal
          final lastDismissed = StorageService.getLastUpdateDismissed();
          if (lastDismissed != null) {
            final diff = DateTime.now().difference(lastDismissed);
            if (diff.inHours < 24) {
              LoggerService.info("🚀 Update: Dismissed recently. Skipping silent check.");
              return;
            }
          }

          // Automatic/Silent check: Start download in background
          LoggerService.info("🚀 Update: New version found. Starting silent background download...");
          _startSilentDownload(remoteName, remote['changelog'] ?? '', apkUrl);
          return;
        }

        // Manual check or Forced: Show the dialog immediately
        LoggerService.info("📢 Update: Naya version mila! v$remoteName (Aapka: v$localName)");
        if (!context.mounted) return;
        
        // Save for potential resume
        _pendingVersion = remoteName;
        _pendingNotes = remote['changelog'];
        _pendingApkUrl = apkUrl;

        _showUpdateDialog(
          context,
          version: remoteName,
          notes: remote['changelog'] ?? 'Performance improvements and bug fixes.',
          apkUrl: apkUrl,
        );
      } else if (!silent && context.mounted) {
        LoggerService.info("✅ Update: Aap latest version (v$localName) par hain.");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ App is up to date"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      LoggerService.error("Update Check Failed", e);
    }
  }

  Future<void> _startSilentDownload(String version, String notes, String apkUrl) async {
    if (_isDownloadingSilently) return;
    _isDownloadingSilently = true;

    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/crm-update-$version.apk';
      final file = File(savePath);
      
      if (await file.exists()) {
        _downloadedApkPath = savePath;
        _isDownloadingSilently = false;
        _notifyReadyToInstall(version, notes, apkUrl);
        return;
      }

      final response = await http.get(Uri.parse(apkUrl)).timeout(const Duration(minutes: 5));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        _downloadedApkPath = savePath;
        LoggerService.info("🚀 Update: Background download complete. v$version is ready.");
        _notifyReadyToInstall(version, notes, apkUrl);
      }
    } catch (e) {
      LoggerService.error("Background Download Failed", e);
    } finally {
      _isDownloadingSilently = false;
    }
  }

  Future<Map<String, dynamic>?> _fetchRemoteVersion() async {
    try {
      LoggerService.info("🌐 Fetching remote version info from: $_versionUrl");
      final response = await http.get(Uri.parse(_versionUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        LoggerService.info("🌐 Remote version fetched successfully.");
        return json.decode(response.body) as Map<String, dynamic>;
      }
      LoggerService.info("🌐 Remote fetch failed: ${response.statusCode}");
      return null;
    } catch (e) {
      LoggerService.info("🌐 Remote fetch error: $e");
      return null;
    }
  }

  void _notifyReadyToInstall(String version, String notes, String apkUrl) {
    // We use the global navigator context to show the dialog once ready
    final context = LoggerService.navKey.currentContext;
    if (context != null && context.mounted) {
      _showUpdateDialog(context, version: version, notes: notes, apkUrl: apkUrl, isReady: true);
    }
  }

  /// Premium Update Dialog
  void _showUpdateDialog(BuildContext context, {
    required String version,
    required String notes,
    required String apkUrl,
    bool isReady = false,
  }) {
    // Check dismissal unless it's a manual check (manual check wouldn't have isReady=true usually unless triggered from dash)
    // Actually, if it's ready, we show it once.
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 10,
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(isReady ? Icons.system_security_update_good_rounded : Icons.auto_awesome, color: const Color(0xFF6366F1), size: 40),
                ),
                const SizedBox(height: 20),
                Text(
                  isReady ? 'Update Ready to Install!' : 'New Update Ready!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(12)),
                  child: Text('v$version', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 16),
                if (notes.isNotEmpty) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("What's New:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: SingleChildScrollView(child: Text(notes, style: const TextStyle(color: Color(0xFF475569), fontSize: 13, height: 1.5))),
                  ),
                  const SizedBox(height: 24),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          StorageService.setUpdateDismissed();
                          Navigator.pop(context);
                        },
                        child: const Text('LATER', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          if (isReady && _downloadedApkPath != null) {
                            _installApk(_downloadedApkPath!, context);
                          } else {
                            _startDownloadFlow(context, apkUrl);
                          }
                        },
                        child: Text(isReady ? 'INSTALL NOW' : 'DOWNLOAD', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _startDownloadFlow(BuildContext context, String apkUrl) async {
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        await Permission.requestInstallPackages.request();
      }
    }

    if (!context.mounted) return;
    
    final outerContext = context;
    showDialog(
      context: outerContext,
      barrierDismissible: false,
      builder: (ctx) => _DownloadProgressDialog(
        apkUrl: apkUrl,
        onInstall: (filePath) => _installApk(filePath, outerContext),
      ),
    );
  }

  Future<void> _installApk(String filePath, BuildContext context) async {
    try {
      final channel = MethodChannel('com.example.crm3/main');
      
      // 🛡️ NATIVE SECURITY CHECK: permission_handler can be inaccurate for this specific permission
      final bool hasNativePermission = await channel.invokeMethod('checkInstallPermission') ?? false;
      
      if (!hasNativePermission) {
        LoggerService.warn("🚀 Update: Native REQUEST_INSTALL_PACKAGES not granted. Redirecting.");
        
        // 🛡️ Set flag to resume when returning
        _isWaitingForPermission = true;

        // Safely close the progress dialog before redirecting
        if (context.mounted && Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        } 
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Please allow 'Install Unknown Apps' for Rynxly CRM to continue."),
              duration: Duration(seconds: 4),
            ),
          );
        }
        
      await channel.invokeMethod('openUnknownSourcesSettings');
      return;
    }

    // 🚀 Update: Triggering installation.
    // No longer closing overlay here as per user request to avoid interference.
    if (context.mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    
    await Future.delayed(const Duration(milliseconds: 200));

    LoggerService.info("🚀 Update: Attempting to open APK at $filePath");
      
      // LAYER 1: Try open_file package
      final result = await OpenFile.open(
        filePath, 
        type: "application/vnd.android.package-archive"
      );
      
      // LAYER 2: ULTIMATE FALLBACK (Native Intent)
      // If open_file fails or reports any error, we use the raw native intent which is 100% stable
      if (result.type != ResultType.done) {
        LoggerService.warn("🚀 Update: open_file failed (${result.message}), falling back to Native Intent");
        await channel.invokeMethod('installApkNative', {'path': filePath});
      }

    } catch (e) {
      LoggerService.error("Critical Installation Failure", e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to launch installer"), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<int> _parseVersion(String v) {
    return v.split('.').map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
  }

  bool _isNewer(List<int> remote, List<int> local) {
    for (var i = 0; i < 3; i++) {
      final r = i < remote.length ? remote[i] : 0;
      final l = i < local.length ? local[i] : 0;
      if (r > l) return true;
      if (r < l) return false;
    }
    return false;
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  final String apkUrl;
  final void Function(String filePath) onInstall;

  const _DownloadProgressDialog({required this.apkUrl, required this.onInstall});

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0;
  String _status = 'Starting download...';
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _download();
  }

  Future<void> _download() async {
    final client = http.Client();
    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/crm-update.apk';
      final file = File(savePath);
      if (await file.exists()) await file.delete();

      final request = http.Request('GET', Uri.parse(widget.apkUrl));
      final response = await client.send(request);

      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();

      DateTime lastUiUpdate = DateTime.now();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        
        final now = DateTime.now();
        if (now.difference(lastUiUpdate).inMilliseconds > 300 || received == total) {
          lastUiUpdate = now;
          if (mounted) {
            setState(() {
              _progress = total > 0 ? received / total : 0;
              _status = '${(received / 1024 / 1024).toStringAsFixed(1)} MB / ${(total / 1024 / 1024).toStringAsFixed(1)} MB';
            });
          }
        }
      }

      await sink.flush();
      await sink.close();
      if (mounted) {
        UpdateService._downloadedApkPath = savePath;
        widget.onInstall(savePath);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = true;
          _status = 'Download failed: $e';
        });
      }
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF6366F1);
    final percentage = (_progress * 100).toInt();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 0,
      backgroundColor: Colors.white,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.05)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Icon with subtle background
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_download_rounded, color: primaryColor, size: 32),
            ),
            const SizedBox(height: 20),
            
            const Text(
              'Downloading Update',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            
            if (!_error) ...[
              Text(
                'Please wait while we prepare the latest version.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 32),
              
              // Progress Bar
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 12,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        backgroundColor: primaryColor.withValues(alpha: 0.1),
                        color: primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Progress Stats
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _status,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                  ),
                  Text(
                    '$percentage%',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryColor),
                  ),
                ],
              ),
            ] else ...[
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                'Download Failed',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent),
              ),
              const SizedBox(height: 8),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade100,
                    foregroundColor: Colors.black87,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
