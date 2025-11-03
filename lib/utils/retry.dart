import 'dart:async';

class Retry {
  static Future<T> retry<T>(
    Future<T> Function() fn, {
    int retries = 3,
    Duration initialDelay = const Duration(seconds: 2),
  }) async {
    Duration delay = initialDelay;
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        return await fn();
      } catch (_) {
        if (attempt == retries) rethrow;
        await Future.delayed(delay);
        delay *= 2;
      }
    }
    throw Exception('unreachable');
  }
}


