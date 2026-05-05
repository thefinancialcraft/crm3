import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/sync_provider.dart';
import '../utils/log_manager.dart' hide LogEntry;

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
        _userScrolling = _scrollController.position.pixels > 0;
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeScrollToTop(int currentLogCount) {
    if (currentLogCount > _lastLogCount && _lastLogCount > 0 && !_userScrolling) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
        }
      });
    }
    _lastLogCount = currentLogCount;
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    final logs = sync.filteredLogs.reversed.toList();
    const primaryColor = Color(0xFF5E17EB);

    _maybeScrollToTop(logs.length);

    return Column(
      children: [
        // Compact Filter Bar
        Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1)))),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildModernChip('ALL', sync.activeFilter == null, () => sync.setFilter(null), primaryColor),
                _buildModernChip('FUNC', sync.activeFilter == LogCategory.function, () => sync.setFilter(LogCategory.function), Colors.indigo),
                _buildModernChip('UI', sync.activeFilter == LogCategory.ui, () => sync.setFilter(LogCategory.ui), Colors.teal),
                VerticalDivider(width: 24, indent: 12, endIndent: 12, color: Colors.grey.withValues(alpha: 0.1)),
                _buildIconButton(Icons.download_rounded, primaryColor, () => _exportLogs(sync.filteredLogs)),
              ],
            ),
          ),
        ),
        // Log List
        Expanded(
          child: Container(
            color: Colors.white,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: logs.length,
              itemExtent: 64, // Fixed height for performance
              itemBuilder: (context, i) => _buildModernLogTile(logs[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModernChip(String label, bool isSelected, VoidCallback onTap, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: isSelected ? color : color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? color : Colors.transparent),
          ),
          child: Center(child: Text(label, style: TextStyle(color: isSelected ? Colors.white : color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5))),
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, Color color, VoidCallback onTap) {
    return IconButton(icon: Icon(icon, size: 20, color: color), onPressed: onTap);
  }

  Widget _buildModernLogTile(LogEntry e) {
    final catColor = e.category == LogCategory.function ? Colors.indigo : Colors.teal;
    final lvlColor = _colorForLevel(e.level);
    final timeStr = '${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}:${e.timestamp.second.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.03)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 3, height: 40, decoration: BoxDecoration(color: lvlColor, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(e.category.name.toUpperCase(), style: TextStyle(color: catColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    const SizedBox(width: 8),
                    Text(timeStr, style: const TextStyle(color: Colors.grey, fontSize: 10, fontFamily: 'monospace')),
                    const Spacer(),
                    if (e.tag.isNotEmpty) Text(e.tag, style: TextStyle(color: Colors.grey.withValues(alpha: 0.6), fontSize: 9, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(e.message, style: const TextStyle(color: Colors.black87, fontSize: 11, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForLevel(LogLevel l) {
    switch (l) {
      case LogLevel.info: return Colors.blue;
      case LogLevel.success: return Colors.green;
      case LogLevel.warning: return Colors.orange;
      case LogLevel.error: return Colors.red;
    }
  }

  Future<void> _exportLogs(List<LogEntry> entries) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'nexus_logs_${DateTime.now().millisecondsSinceEpoch}.txt'));
      final lines = entries.reversed.map((e) => '[${e.category.name}][${e.level.name}] ${e.tag} ${e.message}').join('\n');
      await file.writeAsString(lines);
      await Share.shareXFiles([XFile(file.path)], text: 'Nexus System Logs');
    } catch (_) {}
  }
}
