import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/app_localizations.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Box _settingsBox;
  late Box _profileBox;

  bool _isDark = true;
  bool _isVolunteer = false;
  bool _isShakeEnabled = true;
  bool _isPowerEnabled = true;
  String _selectedLanguage = 'English';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _medicalController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  String _selectedGender = 'Female';
  String _selectedBloodGroup = 'O+';

  @override
  void initState() {
    super.initState();
    _settingsBox = Hive.box('settings');
    _profileBox = Hive.box('profile');
    _loadSettings();
  }

  void _loadSettings() {
    setState(() {
      _isDark = _settingsBox.get('dark_mode', defaultValue: true) as bool;
      _isVolunteer = _settingsBox.get('volunteer_mode', defaultValue: false) as bool;
      _isShakeEnabled = _settingsBox.get('shake_enabled', defaultValue: true) as bool;
      _isPowerEnabled = _settingsBox.get('power_enabled', defaultValue: true) as bool;
      _selectedLanguage = _settingsBox.get('language', defaultValue: 'English') as String;

      // Load Profile Cache details
      final rawProfile = _profileBox.get('user_data', defaultValue: {});
      final profile = Map<String, dynamic>.from(rawProfile as Map);
      _nameController.text = profile['name'] as String? ?? '';
      _ageController.text = profile['age']?.toString() ?? '';
      _medicalController.text = profile['medical_condition'] as String? ?? '';
      _notesController.text = profile['emergency_notes'] as String? ?? '';
      _selectedGender = profile['gender'] as String? ?? 'Female';
      _selectedBloodGroup = profile['blood_group'] as String? ?? 'O+';
    });
  }

  Future<void> _saveProfile() async {
    final profileData = {
      'name': _nameController.text,
      'age': int.tryParse(_ageController.text) ?? 24,
      'gender': _selectedGender,
      'blood_group': _selectedBloodGroup,
      'medical_condition': _medicalController.text,
      'emergency_notes': _notesController.text,
    };

    await _profileBox.put('user_data', profileData);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile details updated successfully.')),
    );
  }

  Future<void> _updateSetting(String key, dynamic value) async {
    await _settingsBox.put(key, value);
    _loadSettings();
  }

  void _resetLocalSettings() async {
    await _settingsBox.clear();
    await _profileBox.clear();
    if (mounted) {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final localization = AppLocalizations(_selectedLanguage);

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.translate('settings')),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDarkTheme ? AppTheme.darkGradient : AppTheme.lightGradient,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. User Profile Custom Settings Form
              Text(
                'Personal Identity Info',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              GlassmorphicContainer(
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.badge)),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Age', prefixIcon: Icon(Icons.calendar_today)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedGender,
                            decoration: const InputDecoration(labelText: 'Gender'),
                            items: ['Female', 'Male', 'Other', 'Prefer not to say']
                                .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                                .toList(),
                            onChanged: (val) => setState(() => _selectedGender = val!),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedBloodGroup,
                            decoration: const InputDecoration(labelText: 'Blood Group'),
                            items: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
                                .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                                .toList(),
                            onChanged: (val) => setState(() => _selectedBloodGroup = val!),
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _medicalController,
                      decoration: const InputDecoration(labelText: 'Medical Condition', prefixIcon: Icon(Icons.medical_services_outlined)),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Emergency Notes', prefixIcon: Icon(Icons.sticky_note_2_outlined)),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentCyan,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(40),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _saveProfile,
                      child: Text(localization.translate('save')),
                    )
                  ],
                ),
              ),

              const SizedBox(height: 30),
              // 2. Preferences & Switches
              Text(
                'Safety Preferences',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              GlassmorphicContainer(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Dark Mode Aesthetics'),
                      value: _isDark,
                      activeColor: AppTheme.accentCyan,
                      onChanged: (val) => _updateSetting('dark_mode', val),
                    ),
                    SwitchListTile(
                      title: const Text('Volunteer Helper Mode'),
                      subtitle: const Text('Receive alerts when nearby community members need assistance'),
                      value: _isVolunteer,
                      activeColor: AppTheme.accentCyan,
                      onChanged: (val) => _updateSetting('volunteer_mode', val),
                    ),
                    SwitchListTile(
                      title: const Text('Shake Sensor SOS'),
                      value: _isShakeEnabled,
                      activeColor: AppTheme.accentCyan,
                      onChanged: (val) => _updateSetting('shake_enabled', val),
                    ),
                    SwitchListTile(
                      title: const Text('Power Key SOS (5 Screen toggles)'),
                      value: _isPowerEnabled,
                      activeColor: AppTheme.accentCyan,
                      onChanged: (val) => _updateSetting('power_enabled', val),
                    ),
                    DropdownButtonListTile(
                      title: 'App Interface Language',
                      value: _selectedLanguage,
                      items: AppLocalizations.supportedLanguages,
                      onChanged: (val) => _updateSetting('language', val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.people_alt_outlined, color: AppTheme.accentCyan),
                title: const Text('Trusted contacts', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Choose who receives your emergency alert'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/trusted-contacts'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey,
                  side: const BorderSide(color: Colors.white24),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Reset Local Settings'),
                onPressed: _resetLocalSettings,
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom dropdown tile helper
class DropdownButtonListTile extends StatelessWidget {
  final String title;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const DropdownButtonListTile({
    super.key,
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 16)),
          DropdownButton<String>(
            value: value,
            items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
