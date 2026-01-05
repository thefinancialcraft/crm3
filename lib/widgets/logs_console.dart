import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/sync_provider.dart';

class LogsConsole extends StatefulWidget {
  const LogsConsole({super.key});

  @override
  State<LogsConsole> createState() => _LogsConsoleState();
}

class _LogsConsoleState extends State<LogsConsole> {
  final ScrollController _scrollController = ScrollController();
  int _lastLogCount = 0;
  bool _userScrolling = false; // Track if user is scrolling

  @override
  void initState() {
    super.initState();

    // Listen to scroll events to detect user scrolling
    _scrollController.addListener(() {
      // Simple approach: if user is scrolling, set flag to true
      // If they scroll to top, set flag to false
      if (_scrollController.hasClients) {
        if (_scrollController.position.pixels > 0) {
          _userScrolling = true;
        } else {
          _userScrolling = false;
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeScrollToTop(int currentLogCount) {
    // Only scroll if a new log was added (count increased) AND user is not scrolling
    if (currentLogCount > _lastLogCount &&
        _lastLogCount > 0 &&
        !_userScrolling) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
    _lastLogCount = currentLogCount;
  }

  Color _colorForLevel(LogLevel l) {
    switch (l) {
      case LogLevel.success:
        return Colors.green.shade700;
      case LogLevel.warning:
        return Colors.orange.shade700;
      case LogLevel.error:
        return Colors.red.shade700;
      case LogLevel.info:
        return Colors.blue.shade700;
    }
  }

  IconData _iconForLevel(LogLevel l) {
    switch (l) {
      case LogLevel.success:
        return Icons.check_circle;
      case LogLevel.warning:
        return Icons.error_outline;
      case LogLevel.error:
        return Icons.error;
      case LogLevel.info:
        return Icons.info_outline;
    }
  }

  Future<void> _exportLogs(List<LogEntry> entries) async {
    try {
      // Reverse back to chronological order for export (oldest first)
      final logsToExport = entries.reversed.toList();

      // Use cache directory (doesn't require permissions on Android 10+)
      final dir = await getTemporaryDirectory();
      final filename =
          'persisted_logs_${DateTime.now().toIso8601String().replaceAll(':', '-')}.txt';
      final file = File(p.join(dir.path, filename));

      // Prepare log content
      final lines = logsToExport
          .map((e) {
            final tagPart = (e.tag.isNotEmpty) ? '[${e.tag}] ' : '';
            final cat = e.category.name.toUpperCase();
            final lvl = e.level.name.toUpperCase();
            return '[$cat][$lvl] $tagPart${e.message} | ${e.timestamp.toIso8601String()}';
          })
          .join('\n');

      // Write to file
      await file.writeAsString(lines);

      // Share file using share_plus (no permissions needed)
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Persisted Logs export (${logsToExport.length} entries)',
        subject: 'CRM3 Persisted Logs',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${logsToExport.length} logs successfully'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (ex) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to export logs: $ex')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    // Reverse logs to show newest first (newest to oldest)
    final logs = sync.filteredLogs.reversed.toList();

    // Auto-scroll to top when new log is added ONLY if user is not scrolling
    _maybeScrollToTop(logs.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Enhanced filter controls with better styling
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF5E17EB).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              // Category filters
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip(
                      context,
                      'All',
                      sync.activeFilter == null,
                      () => sync.setFilter(null),
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      context,
                      'Function',
                      sync.activeFilter == LogCategory.function,
                      () => sync.setFilter(LogCategory.function),
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      context,
                      'UI',
                      sync.activeFilter == LogCategory.ui,
                      () => sync.setFilter(LogCategory.ui),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _exportLogs(sync.filteredLogs),
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Export'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5E17EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Clear logs',
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => sync.clearLogs(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Level filters
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildLevelFilterChip(
                      context,
                      'All levels',
                      sync.activeLevelFilter == null,
                      () => sync.setLevelFilter(null),
                    ),
                    const SizedBox(width: 8),
                    _buildLevelFilterChip(
                      context,
                      'Info',
                      sync.activeLevelFilter == LogLevel.info,
                      () => sync.setLevelFilter(LogLevel.info),
                      Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    _buildLevelFilterChip(
                      context,
                      'Success',
                      sync.activeLevelFilter == LogLevel.success,
                      () => sync.setLevelFilter(LogLevel.success),
                      Colors.green,
                    ),
                    const SizedBox(width: 8),
                    _buildLevelFilterChip(
                      context,
                      'Warning',
                      sync.activeLevelFilter == LogLevel.warning,
                      () => sync.setLevelFilter(LogLevel.warning),
                      Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    _buildLevelFilterChip(
                      context,
                      'Error',
                      sync.activeLevelFilter == LogLevel.error,
                      () => sync.setLevelFilter(LogLevel.error),
                      Colors.red,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Enhanced log display with improved readability
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: logs.length,
              itemBuilder: (context, i) {
                final e = logs[i];
                return _buildLogEntry(e);
              },
            ),
          ),
        ),
      ],
    );
  }

  // New method to build a more user-friendly log entry
  Widget _buildLogEntry(LogEntry e) {
    final color = _colorForLevel(e.level);
    final icon = _iconForLevel(e.level);
    final tag = (e.tag.isNotEmpty) ? '[${e.tag}] ' : '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon, category, level and timestamp
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getCategoryColor(e.category).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  e.category.name.toUpperCase(),
                  style: TextStyle(
                    color: _getCategoryColor(e.category),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  e.level.name.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}:${e.timestamp.second.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Main log message with better formatting
          Text(
            '$tag${e.message}',
            style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onSelected,
  ) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: const Color(0xFF5E17EB),
      backgroundColor: Colors.white,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF5E17EB),
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? const Color(0xFF5E17EB) : Colors.grey,
        ),
      ),
    );
  }

  Widget _buildLevelFilterChip(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onSelected, [
    Color? color,
  ]) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: color ?? const Color(0xFF5E17EB),
      backgroundColor: Colors.white,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        color: selected ? Colors.white : (color ?? const Color(0xFF5E17EB)),
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? (color ?? const Color(0xFF5E17EB)) : Colors.grey,
        ),
      ),
    );
  }

  Color _getCategoryColor(LogCategory category) {
    switch (category) {
      case LogCategory.function:
        return Colors.purple;
      case LogCategory.ui:
        return Colors.blue;
    }
  }
}
