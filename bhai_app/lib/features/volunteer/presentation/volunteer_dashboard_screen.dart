import 'package:flutter/material.dart';

import '../../../core/services/emergency_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../chat/presentation/bluetooth_mesh_chat_dialog.dart';

class VolunteerDashboardScreen extends StatefulWidget {
  const VolunteerDashboardScreen({super.key});

  @override
  State<VolunteerDashboardScreen> createState() => _VolunteerDashboardScreenState();
}

class _VolunteerDashboardScreenState extends State<VolunteerDashboardScreen> {
  final _emergency = EmergencyService();
  bool _loading = true;
  String? _error;
  List<NearbyEmergency> _emergencies = const [];
  final Set<String> _acknowledging = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _emergencies = await _emergency.getNearbyEmergencies();
    } catch (_) {
      _error = 'Could not load nearby requests. Check your helper availability and connection.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _acknowledge(NearbyEmergency event) async {
    setState(() => _acknowledging.add(event.id));
    try {
      await _emergency.acknowledge(event.id, helping: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Response confirmed! Opening navigation to victim...'),
            backgroundColor: Colors.green,
          ),
        );
      }
      if (event.latitude != null && event.longitude != null && (event.latitude != 0.0 || event.longitude != 0.0)) {
        await _emergency.openNavigation(event.latitude!, event.longitude!);
      }
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not acknowledge this emergency. Please call official services if safe.')),
        );
      }
    } finally {
      if (mounted) setState(() => _acknowledging.remove(event.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF020617),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F172A),
          title: Text(
            _emergencies.isEmpty
                ? 'NEARBY BHAI ALERTS'
                : '🚨 ${_emergencies.length} ACTIVE ${_emergencies.length == 1 ? 'EMERGENCY' : 'EMERGENCIES'}',
            style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
          ),
          actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.accentCrimson))
              : _error != null
                  ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)))])
                  : _emergencies.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 160),
                            Icon(Icons.shield_outlined, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('No nearby active emergencies.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
                            SizedBox(height: 8),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 36),
                              child: Text('You will receive an alert as soon as a nearby Bhai user needs assistance.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                            ),
                          ],
                        )
                      : _buildDynamicEmergenciesLayout(),
        ),
      );

  Widget _buildDynamicEmergenciesLayout() {
    final count = _emergencies.length;

    // Rule 1: ONE nearby victim -> Large Primary Card
    if (count == 1) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _singleLargeCard(_emergencies.first),
        ],
      );
    }

    // Rule 2: TWO nearby victims -> Two balanced cards
    if (count == 2) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _balancedCard(_emergencies[0], 'EMERGENCY A'),
          const SizedBox(height: 14),
          _balancedCard(_emergencies[1], 'EMERGENCY B'),
        ],
      );
    }

    // Rule 3: THREE OR MORE -> Scrollable list with compact cards
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _emergencies.length,
      itemBuilder: (context, index) {
        final letter = String.fromCharCode(65 + (index % 26));
        final prefix = index < 26 ? 'EMG-$letter' : 'EMG-${index + 1}';
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _compactCard(_emergencies[index], prefix),
        );
      },
    );
  }

  /// 1 Emergency: Large Primary Card with rich details and full controls
  Widget _singleLargeCard(NearbyEmergency event) {
    final hasCoords = event.latitude != null && event.longitude != null && (event.latitude != 0.0 || event.longitude != 0.0);
    final helperText = event.helperCount == 0
        ? '⚠️ 0 members responding (Urgent Help Needed!)'
        : event.helperCount == 1
            ? '👥 1 member responding'
            : '👥 ${event.helperCount} members responding';
    final helperColor = event.helperCount == 0 ? Colors.amberAccent : Colors.greenAccent;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.accentCrimson, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentCrimson.withOpacity(0.35),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accentCrimson.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: AppTheme.accentCrimson, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🚨 ACTIVE EMERGENCY',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5),
                    ),
                    Text(
                      'Victim ID: ${event.senderId ?? event.id.substring(0, 8)}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF38BDF8)),
                ),
                child: Text(
                  _distance(event.distanceMeters),
                  style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.access_time, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Text('Location updated ${_age(event.triggeredAt)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              if (event.accuracy != null) ...[
                const SizedBox(width: 10),
                Text('• ±${event.accuracy!.toStringAsFixed(0)}m accuracy', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: helperColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: helperColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(event.helperCount == 0 ? Icons.error_outline : Icons.groups, color: helperColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  helperText,
                  style: TextStyle(color: helperColor, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _acknowledging.contains(event.id) ? null : () => _acknowledge(event),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentCrimson,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _acknowledging.contains(event.id)
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.directions_run, size: 22),
              label: const Text("I'M COMING (I CAN HELP)", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => BluetoothMeshChatDialog(alertId: event.id, helperId: event.senderId),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.cyanAccent,
                    side: const BorderSide(color: Colors.cyanAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: const Text('CHAT', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              if (hasCoords) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _emergency.openNavigation(event.latitude!, event.longitude!),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.navigation, size: 18),
                    label: const Text('NAVIGATE', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 2 Emergencies: Balanced Equal-Weight Cards
  Widget _balancedCard(NearbyEmergency event, String label) {
    final hasCoords = event.latitude != null && event.longitude != null && (event.latitude != 0.0 || event.longitude != 0.0);
    final helperColor = event.helperCount == 0 ? Colors.amberAccent : Colors.greenAccent;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.accentCrimson.withOpacity(0.8), width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppTheme.accentCrimson, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '🚨 $label',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Text(
                _distance(event.distanceMeters),
                style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '👥 ${event.helperCount} responding',
                style: TextStyle(color: helperColor, fontWeight: FontWeight.w600, fontSize: 12),
              ),
              Text(
                _age(event.triggeredAt),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _acknowledging.contains(event.id) ? null : () => _acknowledge(event),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accentCrimson,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _acknowledging.contains(event.id)
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("I'M COMING", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => BluetoothMeshChatDialog(alertId: event.id, helperId: event.senderId),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyanAccent,
                  side: const BorderSide(color: Colors.cyanAccent),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('CHAT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              if (hasCoords) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.navigation, color: Colors.white, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  tooltip: 'Navigate',
                  onPressed: () => _emergency.openNavigation(event.latitude!, event.longitude!),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 3+ Emergencies: Compact Scrollable Item with independent actions
  Widget _compactCard(NearbyEmergency event, String code) {
    final hasCoords = event.latitude != null && event.longitude != null && (event.latitude != 0.0 || event.longitude != 0.0);
    final helperColor = event.helperCount == 0 ? Colors.amberAccent : Colors.greenAccent;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.accentCrimson.withOpacity(0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.accentCrimson.withOpacity(0.5)),
            ),
            child: Text(
              code,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _distance(event.distanceMeters),
                      style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• ${_age(event.triggeredAt)}',
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '👥 ${event.helperCount} responding',
                  style: TextStyle(color: helperColor, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline, color: Colors.cyanAccent, size: 20),
            tooltip: 'Chat with Victim',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => BluetoothMeshChatDialog(alertId: event.id, helperId: event.senderId),
              );
            },
          ),
          if (hasCoords)
            IconButton(
              icon: const Icon(Icons.navigation_rounded, color: Colors.greenAccent, size: 20),
              tooltip: 'Navigate',
              onPressed: () => _emergency.openNavigation(event.latitude!, event.longitude!),
            ),
          ElevatedButton(
            onPressed: _acknowledging.contains(event.id) ? null : () => _acknowledge(event),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentCrimson,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: _acknowledging.contains(event.id)
                ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white))
                : const Text("HELP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  String _distance(int meters) => meters < 1000 ? '${meters}m away' : '${(meters / 1000).toStringAsFixed(1)}km away';
  String _age(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

