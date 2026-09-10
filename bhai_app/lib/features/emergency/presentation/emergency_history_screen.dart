import 'package:flutter/material.dart';

import '../../../core/services/api_client.dart';
import '../../../core/theme/app_theme.dart';

class EmergencyHistoryScreen extends StatefulWidget {
  const EmergencyHistoryScreen({super.key});

  @override
  State<EmergencyHistoryScreen> createState() => _EmergencyHistoryScreenState();
}

class _EmergencyHistoryScreenState extends State<EmergencyHistoryScreen> {
  final _api = ApiClient();
  bool _loading = true;
  List<Map<String, dynamic>> _events = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.get('/emergencies/history') as List<dynamic>;
      _events = data.map((event) => Map<String, dynamic>.from(event as Map)).toList();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Emergency History')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _events.isEmpty
                ? const Center(child: Text('No emergency history.'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _events.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (_, index) {
                        final event = _events[index];
                        final active = event['status'] == 'ACTIVE';
                        final date = DateTime.tryParse(event['triggered_at'].toString())?.toLocal();
                        return ListTile(
                          leading: Icon(active ? Icons.warning_amber_rounded : Icons.check_circle_outline, color: active ? AppTheme.accentCrimson : Colors.green),
                          title: Text(active ? 'Emergency active' : 'Emergency ended'),
                          subtitle: Text(date?.toString() ?? 'Unknown time'),
                          trailing: Text(active ? 'ACTIVE' : 'ENDED', style: TextStyle(color: active ? AppTheme.accentCrimson : Colors.green, fontWeight: FontWeight.bold)),
                        );
                      },
                    ),
                  ),
      );
}
