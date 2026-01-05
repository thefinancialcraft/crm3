import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/sync_provider.dart';

class LogViewer extends StatefulWidget {
  const LogViewer({super.key});

  @override
  State<LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends State<LogViewer> {
  final ScrollController _scrollController = ScrollController();
  int _lastLogCount = 0;
  bool _userScrolling = false;

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(() {
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
        return const Color(0xFF4CAF50); // Bright green
      case LogLevel.warning:
        return const Color(0xFFFFA726); // Bright orange
      case LogLevel.error:
        return const Color(0xFFEF5350); // Bright red
      case LogLevel.info:
        return const Color(0xFF42A5F5); // Bright blue
    }
  }

  Future<void> _exportLogs(List<LogEntry> entries) async {
    try {
      final logsToExport = entries.reversed.toList();

      final dir = await getTemporaryDirectory();
      final filename =
          'log_viewer_export_${DateTime.now().toIso8601String().replaceAll(':', '-')}.txt';
      final file = File(p.join(dir.path, filename));

      final lines = logsToExport
          .map((e) {
            final tagPart = (e.tag.isNotEmpty) ? '[${e.tag}] ' : '';
            final cat = e.category.name.toUpperCase();
            final lvl = e.level.name.toUpperCase();
            return '[$cat][$lvl] $tagPart${e.message} | ${e.timestamp.toIso8601String()}';
          })
          .join('\n');

      await file.writeAsString(lines);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Log Viewer export (${logsToExport.length} entries)',
        subject: 'Log Viewer Export',
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
    final logs = sync.filteredLogs.reversed.toList();

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
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E), // Dark background like console
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

  Widget _buildLogEntry(LogEntry e) {
    final color = _colorForLevel(e.level);
    final levelPrefix = _getLevelPrefix(e.level);
    final tag = (e.tag.isNotEmpty) ? '[${e.tag}] ' : '';
    final timestamp =
        '${e.timestamp.month.toString().padLeft(2, '0')}-${e.timestamp.day.toString().padLeft(2, '0')} ${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}:${e.timestamp.second.toString().padLeft(2, '0')}.${(e.timestamp.millisecond).toString().padLeft(3, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: SelectableText(
        '$timestamp $levelPrefix${e.category.name.toLowerCase()}: $tag${e.message}',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: color,
          height: 1.4,
        ),
      ),
    );
  }

  String _getLevelPrefix(LogLevel l) {
    switch (l) {
      case LogLevel.success:
        return '';
      case LogLevel.warning:
        return 'W/';
      case LogLevel.error:
        return 'E/';
      case LogLevel.info:
        return 'I/';
    }
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
}
