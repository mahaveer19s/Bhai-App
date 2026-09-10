import 'package:flutter/material.dart';

import '../../../core/services/emergency_service.dart';
import '../../../core/theme/app_theme.dart';

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
          const SnackBar(content: Text('The protected user has been told that a nearby BHAI is helping.')),
        );
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
        appBar: AppBar(
          title: const Text('NEARBY BHAI ALERTS'),
          actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center))])
                  : _emergencies.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 160),
                            Icon(Icons.shield_outlined, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('No nearby active emergencies.', textAlign: TextAlign.center),
                            SizedBox(height: 8),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 36),
                              child: Text('BHAI never shows an exact location until you choose to help.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _emergencies.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, index) => _card(_emergencies[index]),
                        ),
        ),
      );

  Widget _card(NearbyEmergency event) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppTheme.accentCrimson),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('BHAI HELP ALERT', style: TextStyle(fontWeight: FontWeight.bold))),
                  Text(_distance(event.distanceMeters), style: const TextStyle(color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 10),
              Text('Requested ${_age(event.triggeredAt)}. Exact location is protected until you accept.'),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _acknowledging.contains(event.id) ? null : () => _acknowledge(event),
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.accentCrimson),
                  child: _acknowledging.contains(event.id)
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('I CAN HELP'),
                ),
              ),
            ],
          ),
        ),
      );

  String _distance(int meters) => meters < 1000 ? '${meters}m away' : '${(meters / 1000).toStringAsFixed(1)}km away';
  String _age(DateTime time) {
    final minutes = DateTime.now().difference(time).inMinutes;
    return minutes <= 0 ? 'just now' : '$minutes min ago';
  }
}
