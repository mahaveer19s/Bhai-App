import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/admin_api.dart';
import '../../../core/url_helper.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _api = AdminApi();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _events = const [];
  String _selectedFilter = 'ALL';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) => _loadQuietly());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.get('/admin/dashboard'),
        _api.get('/admin/emergencies'),
      ]);
      _stats = Map<String, dynamic>.from(results[0] as Map);
      _events = (results[1] as List<dynamic>).map((event) => Map<String, dynamic>.from(event as Map)).toList();
    } catch (error) {
      _error = error.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadQuietly() async {
    try {
      final results = await Future.wait([
        _api.get('/admin/dashboard'),
        _api.get('/admin/emergencies'),
      ]);
      if (mounted) {
        setState(() {
          _stats = Map<String, dynamic>.from(results[0] as Map);
          _events = (results[1] as List<dynamic>).map((event) => Map<String, dynamic>.from(event as Map)).toList();
        });
      }
    } catch (_) {}
  }

  void _openGoogleMaps(double lat, double lon) {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon';
    openUrl(url);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening Google Maps navigation for $lat, $lon in new tab...'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showLocationDialog(Map<String, dynamic> event) {
    final lat = (event['last_latitude'] ?? event['initial_latitude'] ?? 0.0) as num;
    final lon = (event['last_longitude'] ?? event['initial_longitude'] ?? 0.0) as num;
    final accuracy = (event['last_accuracy'] ?? event['initial_accuracy'] ?? 10.0) as num;
    final when = DateTime.tryParse(event['triggered_at'].toString())?.toLocal().toString() ?? 'Unknown time';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.location_pin, color: Colors.redAccent, size: 28),
            const SizedBox(width: 8),
            const Text('Emergency Location Detail', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Emergency ID: ${event['id']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Latitude / Longitude', style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18, color: Colors.cyan),
                        tooltip: 'Copy Coordinates',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: '$lat, $lon'));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Coordinates copied to clipboard!')),
                          );
                        },
                      ),
                    ],
                  ),
                  SelectableText(
                    'Lat: $lat\nLon: $lon',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Text('GPS Accuracy: ±${accuracy.toStringAsFixed(1)} m', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  Text('Trigger Time: $when', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            icon: const Icon(Icons.map, color: Colors.white),
            label: const Text('🗺️ OPEN GOOGLE MAPS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.pop(context);
              _openGoogleMaps(lat.toDouble(), lon.toDouble());
            },
          ),
        ],
      ),
    );
  }

  void _showTimeline(Map<String, dynamic> event) {
    final active = event['status'] == 'ACTIVE';
    final when = DateTime.tryParse(event['triggered_at'].toString())?.toLocal().toString() ?? 'Unknown time';
    final lat = (event['last_latitude'] ?? event['initial_latitude'] ?? 0.0) as num;
    final lon = (event['last_longitude'] ?? event['initial_longitude'] ?? 0.0) as num;
    final helpers = event['helper_count'] ?? 0;
    final alerted = event['alerted_count'] ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Emergency Audit Timeline', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  Chip(
                    label: Text(event['status'].toString()),
                    backgroundColor: active ? Colors.red.withOpacity(.2) : Colors.green.withOpacity(.2),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Emergency ID: ${event['id']}', style: const TextStyle(color: Colors.grey)),
              Text('Triggered: $when', style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.blue.withOpacity(.15), borderRadius: BorderRadius.circular(8)),
                    child: Text('Alerted: $alerted users', style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.green.withOpacity(.15), borderRadius: BorderRadius.circular(8)),
                    child: Text('Going to Help: $helpers responders', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const Divider(height: 32),
              const Text('Geospatial Map Coordinates', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    const Icon(Icons.map_outlined, color: Colors.cyan),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText('Lat: $lat, Lon: $lon', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('Accuracy radius: ${event['last_accuracy'] ?? 10}m', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                      icon: const Icon(Icons.navigation, size: 16, color: Colors.white),
                      label: const Text('🗺️ GOOGLE MAPS', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => _openGoogleMaps(lat.toDouble(), lon.toDouble()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text('Event Timeline Log (Audit Trail)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _timelineTile('Emergency Triggered', when, Icons.bolt, Colors.red),
              _timelineTile('Location Fix Captured', 'GPS coordinates ($lat, $lon)', Icons.my_location, Colors.blue),
              _timelineTile('BLE Store-and-Forward Discovery', 'Dual-rail BLE radio and internet queued', Icons.bluetooth, Colors.cyan),
              _timelineTile('Server Synchronized', event['created_at']?.toString() ?? when, Icons.cloud_done, Colors.green),
              _timelineTile('Responders Dispatched', '$helpers nearby users opted "I\'m Going to Help"', Icons.security, Colors.orange),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timelineTile(String title, String subtitle, IconData icon, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: color.withOpacity(.15), radius: 18, child: Icon(icon, color: color, size: 18)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('BHAI RESPONSE CENTER'),
          actions: [
            DropdownButton<String>(
              value: _selectedFilter,
              dropdownColor: const Color(0xFF0F172A),
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('All Statuses')),
                DropdownMenuItem(value: 'ACTIVE', child: Text('Active Only')),
                DropdownMenuItem(value: 'ENDED', child: Text('Resolved Only')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedFilter = val);
              },
            ),
            const SizedBox(width: 12),
            IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const Text('Regional Control Room', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        const Text('Live data is restricted to authorized emergency control-room operators and audited by API.'),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: [
                            _stat('Active emergencies', _stats!['active_emergencies'], Colors.red),
                            _stat('Resolved emergencies', _stats!['resolved_emergencies'], Colors.green),
                            _stat('Registered users', _stats!['total_users'], Colors.cyan),
                            _stat('Helper acknowledgements', _stats!['helper_acknowledgements'], Colors.orange),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Emergency Incidents', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            Text('${_filteredEvents.length} items', style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_filteredEvents.isEmpty)
                          const Padding(padding: EdgeInsets.all(24), child: Text('No matching emergency records found.')),
                        ..._filteredEvents.map(_event),
                      ],
                    ),
                  ),
      );

  List<Map<String, dynamic>> get _filteredEvents {
    if (_selectedFilter == 'ALL') return _events;
    return _events.where((e) => e['status'] == _selectedFilter).toList();
  }

  Widget _stat(String label, dynamic value, Color color) => SizedBox(
        width: 210,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              Text('$value', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
            ]),
          ),
        ),
      );

  Widget _event(Map<String, dynamic> event) {
    final active = event['status'] == 'ACTIVE';
    final when = DateTime.tryParse(event['triggered_at'].toString())?.toLocal().toString() ?? 'Unknown time';
    final lat = (event['last_latitude'] ?? event['initial_latitude'] ?? 0.0) as num;
    final lon = (event['last_longitude'] ?? event['initial_longitude'] ?? 0.0) as num;
    final helpers = event['helper_count'] ?? 0;
    final alerted = event['alerted_count'] ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(active ? Icons.warning_amber_rounded : Icons.check_circle_outline, color: active ? Colors.red : Colors.green, size: 24),
                    const SizedBox(width: 10),
                    Text(
                      'Emergency ${event['id'].toString().substring(0, 8)}...',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Chip(
                  label: Text(event['status'].toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  backgroundColor: active ? Colors.red.withOpacity(.2) : Colors.green.withOpacity(.2),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Triggered: $when', style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.my_location, size: 14, color: Colors.cyan),
                const SizedBox(width: 4),
                SelectableText('GPS: $lat, $lon', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.blue.withOpacity(.12), borderRadius: BorderRadius.circular(6)),
                  child: Text('👥 Alerted: $alerted', style: const TextStyle(fontSize: 12, color: Colors.lightBlueAccent, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(.12), borderRadius: BorderRadius.circular(6)),
                  child: Text('🏃 Going to Help: $helpers', style: const TextStyle(fontSize: 12, color: Colors.lightGreenAccent, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.map, size: 16, color: Colors.white),
                  label: const Text('🗺️ OPEN GOOGLE MAPS', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => _openGoogleMaps(lat.toDouble(), lon.toDouble()),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.cyanAccent,
                    side: const BorderSide(color: Colors.cyanAccent),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.location_on_outlined, size: 16),
                  label: const Text('📍 OPEN LOCATION', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => _showLocationDialog(event),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('Timeline', style: TextStyle(fontSize: 12)),
                  onPressed: () => _showTimeline(event),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
