import 'package:flutter/material.dart';

import '../../../core/services/api_client.dart';
import '../../../core/theme/app_theme.dart';

class TrustedContactsScreen extends StatefulWidget {
  const TrustedContactsScreen({super.key});

  @override
  State<TrustedContactsScreen> createState() => _TrustedContactsScreenState();
}

class _TrustedContactsScreenState extends State<TrustedContactsScreen> {
  final _api = ApiClient();
  bool _loading = true;
  List<Map<String, dynamic>> _contacts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.get('/trusted-contacts') as List<dynamic>;
      _contacts = data.map((entry) => Map<String, dynamic>.from(entry as Map)).toList();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addContact() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final relationship = TextEditingController();
    final save = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Add trusted contact'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name')),
                  TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number with country code')),
                  TextField(controller: relationship, decoration: const InputDecoration(labelText: 'Relationship (optional)')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('SAVE')),
            ],
          ),
        ) ??
        false;
    if (!save || name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
    try {
      await _api.post('/trusted-contacts', {
        'name': name.text.trim(),
        'phone': phone.text.trim(),
        'relationship': relationship.text.trim().isEmpty ? null : relationship.text.trim(),
      });
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      name.dispose();
      phone.dispose();
      relationship.dispose();
    }
  }

  Future<void> _remove(String id) async {
    try {
      await _api.delete('/trusted-contacts/$id');
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Trusted Contacts')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addContact,
          backgroundColor: AppTheme.accentCrimson,
          icon: const Icon(Icons.person_add),
          label: const Text('ADD CONTACT'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _contacts.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Text('Add people you trust. BHAI will notify active trusted contacts when an emergency is created.', textAlign: TextAlign.center),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _contacts.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, index) {
                      final contact = _contacts[index];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                        title: Text(contact['name'].toString()),
                        subtitle: Text('${contact['relationship'] ?? 'Trusted contact'} • ${contact['phone']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppTheme.accentCrimson),
                          tooltip: 'Remove contact',
                          onPressed: () => _remove(contact['id'].toString()),
                        ),
                      );
                    },
                  ),
      );
}
