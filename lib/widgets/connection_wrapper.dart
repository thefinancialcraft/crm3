import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../pages/offline_page.dart';
import '../services/logger_service.dart';

class ConnectionWrapper extends StatefulWidget {
  final Widget child;

  const ConnectionWrapper({super.key, required this.child});

  @override
  State<ConnectionWrapper> createState() => _ConnectionWrapperState();
}

class _ConnectionWrapperState extends State<ConnectionWrapper> {
  List<ConnectivityResult> _connectionStatus = [ConnectivityResult.none];
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initConnectivity();

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectionStatus,
    );
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  Future<void> _initConnectivity() async {
    late List<ConnectivityResult> result;
    try {
      result = await _connectivity.checkConnectivity();
    } catch (e) {
      LoggerService.error('Couldn\'t check connectivity status', e);
      return;
    }

    if (!mounted) {
      return Future.value(null);
    }

    return _updateConnectionStatus(result);
  }

  Future<void> _updateConnectionStatus(List<ConnectivityResult> result) async {
    setState(() {
      _connectionStatus = result;
      _initialized = true;
    });
    LoggerService.info('Connectivity changed: $result');
  }

  bool _isOffline(List<ConnectivityResult> results) {
    if (results.isEmpty) {
      return true;
    }
    if (results.length == 1 && results.first == ConnectivityResult.none) {
      return true;
    }
    // You might want to handle other cases, but typically 'none' means offline.
    // connectivity_plus v6: [ConnectivityResult.none] is returned when disconnected.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // While initializing, we can show child or a loading, but child is safer to avoid flicker if online.
    if (!_initialized) {
      return widget.child;
    }

    if (_isOffline(_connectionStatus)) {
      return OfflinePage(
        onReload: () {
          _initConnectivity();
        },
      );
    }

    return widget.child;
  }
}
