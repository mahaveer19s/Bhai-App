import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/database/database_service.dart';

class HelplineScreen extends StatefulWidget {
  const HelplineScreen({super.key});

  @override
  State<HelplineScreen> createState() => _HelplineScreenState();
}

class _HelplineScreenState extends State<HelplineScreen> {
  final TextEditingController _searchController = TextEditingController();
  final _databaseService = DatabaseService();
  List<Map<String, dynamic>> _helplines = [];
  bool _isLoading = false;

  final List<Map<String, dynamic>> _defaultHelplines = [
    {'id': '1', 'state': 'National', 'category': 'Police', 'number': '112', 'name': 'National Emergency Response'},
    {'id': '2', 'state': 'National', 'category': 'Women Helpline', 'number': '1091', 'name': 'Women Helpline (Domestic Violence)'},
    {'id': '3', 'state': 'National', 'category': 'Women Helpline', 'number': '181', 'name': 'Women Helpline (General Assistance)'},
    {'id': '4', 'state': 'National', 'category': 'Child Helpline', 'number': '1098', 'name': 'Child Abuse & Protection Line'},
    {'id': '5', 'state': 'National', 'category': 'Ambulance', 'number': '102', 'name': 'National Medical Emergency Service'},
    {'id': '6', 'state': 'National', 'category': 'Fire', 'number': '101', 'name': 'Fire Control Desk'},
    {'id': '7', 'state': 'National', 'category': 'Railway Police', 'number': '1512', 'name': 'Railway Protection Force'},
    {'id': '8', 'state': 'National', 'category': 'Cyber Crime', 'number': '1930', 'name': 'National Cyber Crime HelpDesk'},
    {'id': '9', 'state': 'Delhi NCR', 'category': 'Police', 'number': '100', 'name': 'Delhi Police Control Room'},
    {'id': '10', 'state': 'Uttar Pradesh', 'category': 'Women Commission', 'number': '1090', 'name': 'UP Women Power Line'}
  ];

  @override
  void initState() {
    super.initState();
    _loadHelplineDirectory();
  }

  Future<void> _loadHelplineDirectory() async {
    setState(() => _isLoading = true);
    
    // Seed default helplines into SQLite to verify offline directory lookup
    await _databaseService.cacheHelplines(_defaultHelplines);
    final results = await _databaseService.searchHelplines('');
    
    setState(() {
      _helplines = results;
      _isLoading = false;
    });
  }

  Future<void> _onSearchChanged(String query) async {
    final results = await _databaseService.searchHelplines(query);
    setState(() {
      _helplines = results;
    });
  }

  void _callNumber(String number) {
    debugPrint('Launching Dialer for: tel:$number');
    // In production: launchUrl(Uri.parse('tel:$number'));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('HELPLINE DIRECTORY'),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkGradient : AppTheme.lightGradient,
        ),
        child: Column(
          children: [
            // Search Input Panel
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextFormField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search by state, name, or category...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty 
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Theme.of(context).cardColor.withOpacity(0.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ),

            // Directory List
            Expanded(
              child: _isLoading 
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.accentCyan))
                  : _helplines.isEmpty 
                      ? const Center(child: Text('No helpline numbers found.'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _helplines.length,
                          itemBuilder: (context, index) {
                            final line = _helplines[index];
                            return _buildHelplineCard(
                              line['name'] as String,
                              line['number'] as String,
                              line['category'] as String,
                              line['state'] as String,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelplineCard(String name, String number, String category, String state) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppTheme.accentCyan.withOpacity(0.15),
          child: const Icon(Icons.phone_in_talk, color: AppTheme.accentCyan),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Number: $number', style: const TextStyle(color: AppTheme.accentCrimson, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(category, style: const TextStyle(fontSize: 10)),
                ),
                const SizedBox(width: 8),
                Text(state, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            )
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.call, color: Colors.green, size: 28),
          onPressed: () => _callNumber(number),
        ),
      ),
    );
  }
}
