import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';
import 'inapp_webview_page.dart';
import '../widgets/connection_wrapper.dart';
import '../services/consent_service.dart';

class SimSelectionPage extends StatefulWidget {
  final bool isFromSettings;
  const SimSelectionPage({super.key, this.isFromSettings = false});

  @override
  State<SimSelectionPage> createState() => _SimSelectionPageState();
}



class _SimSelectionPageState extends State<SimSelectionPage> {
  bool _isLoading = true;
  String? _selectedSimId;
  int? _selectedSlotIndex;

  @override
  void initState() {
    super.initState();
    _loadSims();
  }

  Future<void> _loadSims() async {
    final syncProvider = context.read<SyncProvider>();
    await syncProvider.refreshSims();
    
    if (mounted) {
      setState(() {
        _isLoading = false;
        _selectedSimId = syncProvider.defaultSimId;
        _selectedSlotIndex = syncProvider.defaultSimSlot;
        
        // Auto-select if only one SIM and nothing selected
        if (syncProvider.availableSims.length == 1 && _selectedSimId == null) {
          _selectedSimId = syncProvider.availableSims.first['id']?.toString();
          _selectedSlotIndex = syncProvider.availableSims.first['slotIndex'] as int?;
        }
      });
    }
  }

  void _handleContinue() async {
    if (_selectedSimId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a primary SIM card')),
      );
      return;
    }

    final syncProvider = context.read<SyncProvider>();
    await syncProvider.setDefaultSim(_selectedSimId, _selectedSlotIndex);

    // 🛡️ Mark onboarding as finished so ConsentPage doesn't reappear
    await ConsentService.markOnboardingComplete();

    if (mounted) {
      if (widget.isFromSettings) {
        Navigator.pop(context);
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => Material(
              color: Colors.white,
              child: ConnectionWrapper(child: const InAppWebViewPage()),
            ),
          ),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncProvider = context.watch<SyncProvider>();
    final sims = syncProvider.availableSims;

    return Scaffold(
        backgroundColor: Colors.white,
        appBar: widget.isFromSettings
            ? AppBar(
                title: const Text('Primary SIM Selection'),
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 0,
              )
            : null,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.isFromSettings) const SizedBox(height: 48),
                if (!widget.isFromSettings) ...[
                  // Icon Header
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.sim_card_outlined,
                        color: Colors.blue, size: 32),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Select Primary SIM',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Choose the SIM card you want to use for CRM calls and synchronization.',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 40),
                if (_isLoading)
                  const Center(
                      child: Padding(
                    padding: EdgeInsets.all(40.0),
                    child: CircularProgressIndicator(),
                  ))
                else if (sims.isEmpty)
                  _buildNoSims()
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: sims.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final sim = sims[index];
                        final id = sim['id']?.toString();
                        final label = sim['label']?.toString() ?? 'Unknown SIM';
                        final slot = sim['slotIndex'] as int?;
                        final isSelected = _selectedSimId == id;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedSimId = id;
                              _selectedSlotIndex = slot;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.blue.withValues(alpha: 0.05)
                                  : Colors.grey[50],
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? Colors.blue : Colors.grey[200]!,
                                width: 2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.blue : Colors.grey[300],
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.sim_card,
                                      color: Colors.white),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.w600,
                                          color: isSelected
                                              ? Colors.blue[900]
                                              : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Slot ${slot != null ? slot + 1 : "Unknown"} | MCC: ${sim['mcc'] ?? "-"} | MNC: ${sim['mnc'] ?? "-"}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle,
                                      color: Colors.blue, size: 28),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 24),
                // Continue Button
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed:
                        _isLoading || sims.isEmpty ? null : _handleContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      sims.length <= 1 ? 'Continue' : 'Set as Primary',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      );
  }

  Widget _buildNoSims() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sim_card_alert_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'No SIM cards detected',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Please insert a SIM card and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: _loadSims,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
