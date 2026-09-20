import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalStorage {
  static final LocalStorage _instance = LocalStorage._internal();
  factory LocalStorage() => _instance;
  LocalStorage._internal();

  late Box _settingsBox;
  late Box _profileBox;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  Future<void> init() async {
    _settingsBox = await Hive.openBox('settings');
    _profileBox = await Hive.openBox('profile');
  }

  // --- Theme & Language ---

  bool get isDarkMode => _settingsBox.get('dark_mode', defaultValue: true) as bool;
  Future<void> setDarkMode(bool val) async => await _settingsBox.put('dark_mode', val);

  String get language => _settingsBox.get('language', defaultValue: 'English') as String;
  Future<void> setLanguage(String lang) async => await _settingsBox.put('language', lang);

  // --- Volunteer Mode Toggles ---

  bool get isVolunteerMode => _settingsBox.get('volunteer_mode', defaultValue: false) as bool;
  Future<void> setVolunteerMode(bool val) async => await _settingsBox.put('volunteer_mode', val);

  // --- Network API Configuration ---

  String? get customApiUrl {
    if (!Hive.isBoxOpen('settings')) return null;
    return Hive.box('settings').get('custom_api_url') as String?;
  }

  Future<void> setCustomApiUrl(String? url) async {
    if (url == null || url.trim().isEmpty) {
      await _settingsBox.delete('custom_api_url');
    } else {
      await _settingsBox.put('custom_api_url', url.trim());
    }
  }

  // --- Auth Session Caching ---

  Future<String?> getToken() => _secureStorage.read(key: 'bhai_access_token');
  Future<void> setToken(String? token) async {
    if (token == null) {
      await _secureStorage.delete(key: 'bhai_access_token');
    } else {
      await _secureStorage.write(key: 'bhai_access_token', value: token);
    }
  }

  String? get userId => _settingsBox.get('user_id') as String?;
  Future<void> setUserId(String? id) async => await _settingsBox.put('user_id', id);

  String getOrGenerateBhaiDeviceId() {
    try {
      if (Hive.isBoxOpen('settings')) {
        var id = _settingsBox.get('bhai_device_id') as String?;
        if (id != null && id.isNotEmpty) return id;
        final now = DateTime.now().millisecondsSinceEpoch;
        final part1 = (now & 0xFFFF).toRadixString(16).padLeft(4, '0').toUpperCase();
        final part2 = ((now ~/ 1000) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
        id = '$part1$part2';
        _settingsBox.put('bhai_device_id', id);
        return id;
      }
    } catch (_) {}
    return 'B4C9E2';
  }

  // --- User Profile Details Cache ---

  Map<String, dynamic>? getCachedProfile() {
    final raw = _profileBox.get('user_data');
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<void> cacheProfile(Map<String, dynamic> data) async {
    await _profileBox.put('user_data', data);
  }

  Future<void> clearSession() async {
    await _secureStorage.delete(key: 'bhai_access_token');
    await _settingsBox.delete('user_id');
    await _profileBox.delete('user_data');
  }

  bool get isEmergencyActive {
    if (!Hive.isBoxOpen('settings')) return false;
    return Hive.box('settings').get('emergency_active', defaultValue: false) as bool;
  }

  String? get activeLocalEmergencyId {
    if (!Hive.isBoxOpen('settings')) return null;
    return Hive.box('settings').get('active_local_emergency_id') as String?;
  }

  String? get activeRemoteEmergencyId {
    if (!Hive.isBoxOpen('settings')) return null;
    return Hive.box('settings').get('active_remote_emergency_id') as String?;
  }

  Future<void> setActiveEmergency({required String localId, String? remoteId}) async {
    await _settingsBox.put('emergency_active', true);
    await _settingsBox.put('active_local_emergency_id', localId);
    if (remoteId != null) await _settingsBox.put('active_remote_emergency_id', remoteId);
  }

  Future<void> setRemoteEmergencyId(String remoteId) async =>
      await _settingsBox.put('active_remote_emergency_id', remoteId);

  Future<void> clearActiveEmergency() async {
    await _settingsBox.delete('emergency_active');
    await _settingsBox.delete('active_local_emergency_id');
    await _settingsBox.delete('active_remote_emergency_id');
  }
}
