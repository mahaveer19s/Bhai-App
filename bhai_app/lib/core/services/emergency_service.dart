import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../database/database_service.dart';
import '../protocol/emergency_packet.dart';
import '../security/security_service.dart';
import '../state/emergency_state_machine.dart';
import '../storage/local_storage.dart';
import 'api_client.dart';
import 'audio_service.dart';
import 'bluetooth_service.dart';
import 'location_service.dart';
import 'notification_service.dart';

class LocationUnavailableException implements Exception {
  const LocationUnavailableException();
}

class EmergencySnapshot {
  const EmergencySnapshot({required this.localId, this.remoteId, required this.isQueued});
  final String localId;
  final String? remoteId;
  final bool isQueued;
}

class NearbyEmergency {
  const NearbyEmergency({
    required this.id,
    required this.distanceMeters,
    required this.triggeredAt,
    this.latitude,
    this.longitude,
  });
  final String id;
  final int distanceMeters;
  final DateTime triggeredAt;
  final double? latitude;
  final double? longitude;

  factory NearbyEmergency.fromJson(Map<String, dynamic> json) => NearbyEmergency(
        id: json['id'].toString(),
        distanceMeters: (json['distance_meters'] as num?)?.round() ?? 0,
        triggeredAt: DateTime.tryParse(json['triggered_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );
}


class EmergencyService {
  EmergencyService._();
  static final EmergencyService _instance = EmergencyService._();
  factory EmergencyService() => _instance;

  final _api = ApiClient();
  final _database = DatabaseService();
  final _security = SecurityService();
  final _storage = LocalStorage();
  final _location = LocationService();
  final _bluetooth = BluetoothService();
  final _stateMachine = EmergencyStateMachine();
  StreamSubscription<Position>? _locationSubscription;

  bool get isActive => _storage.isEmergencyActive;
  String? get activeEmergencyId => _storage.activeRemoteEmergencyId;
  EmergencyState get currentState => _stateMachine.currentState;

  String _id(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<void> resumeActiveEmergency() async {
    final localId = _storage.activeLocalEmergencyId;
    if (!isActive || localId == null) return;
    _stateMachine.transitionTo(EmergencyState.activeEmergency, reason: 'Resumed active emergency');
    await _bluetooth.startSosAdvertising(_security.hashSha256(localId).substring(0, 16));
    await NotificationService().showEmergencyActive();
    _startLocationUpdates(localId);
    await syncPending();
  }

  Future<EmergencySnapshot> activate({bool isTest = false}) => activateFast(isTest: isTest);

  /// Immediate fast-path SOS activation (<50ms local UI response).
  /// Activates local emergency state, siren, and notifications instantly,
  /// then executes GPS, BLE broadcasting, and internet syncing in parallel.
  Future<EmergencySnapshot> activateFast({bool isTest = false}) async {
    final clientSosTimestamp = DateTime.now().toUtc();
    if (isActive) {
      return EmergencySnapshot(
        localId: _storage.activeLocalEmergencyId ?? 'active',
        remoteId: _storage.activeRemoteEmergencyId,
        isQueued: _storage.activeRemoteEmergencyId == null,
      );
    }

    final localId = _id('bhai');
    _stateMachine.transitionTo(EmergencyState.activeEmergency, reason: 'BHAI Button Activated (Fast Path)');
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    // Persist active state locally immediately
    await _storage.setActiveEmergency(localId: localId);

    // Start local audio siren & notification immediately without awaiting network/GPS
    try {
      AudioAlertService().startSiren();
    } catch (_) {}
    try {
      NotificationService().showEmergencyActive();
    } catch (_) {}

    // Parallel Asynchronous Dispatch (Non-blocking)
    unawaited(_executeParallelEmergencyDispatch(
      localId: localId,
      clientSosTimestamp: clientSosTimestamp,
      isTest: isTest,
    ));

    return EmergencySnapshot(localId: localId, remoteId: null, isQueued: true);
  }

  Future<void> _executeParallelEmergencyDispatch({
    required String localId,
    required DateTime clientSosTimestamp,
    required bool isTest,
  }) async {
    // 1. Start BLE emergency broadcast immediately with radio
    try {
      unawaited(_bluetooth.startEmergencyBroadcast(emergencyId: localId));
    } catch (_) {}

    // 2. Parallel GPS acquisition
    Position? position;
    try {
      position = await _location.getBestAvailableLocation().timeout(const Duration(seconds: 4));
    } catch (_) {}

    // Update BLE broadcast with exact GPS coordinates if available
    if (position != null) {
      try {
        unawaited(_bluetooth.startEmergencyBroadcast(
          latitude: position.latitude,
          longitude: position.longitude,
          emergencyId: localId,
        ));
      } catch (_) {}
    }

    final packet = EmergencyPacket(
      protocolVersion: 1,
      messageId: _id('msg'),
      emergencyId: localId,
      type: 'EMERGENCY',
      createdAt: clientSosTimestamp.toIso8601String(),
      expiresAt: clientSosTimestamp.add(const Duration(hours: 6)).toIso8601String(),
      senderEphemeralId: _security.hashSha256(localId).substring(0, 12),
      latitude: position?.latitude ?? 0.0,
      longitude: position?.longitude ?? 0.0,
      accuracy: position?.accuracy ?? 0.0,
      locationSource: position != null ? 'GPS' : 'NONE',
      locationTimestamp: DateTime.now().toUtc().toIso8601String(),
      severity: 'HIGH',
      hopCount: 0,
      maxHops: 3,
      requiresRelay: true,
      isTest: isTest,
      signature: '',
    );

    final payload = <String, dynamic>{
      'idempotency_key': localId,
      'latitude': position?.latitude ?? 0.0,
      'longitude': position?.longitude ?? 0.0,
      'accuracy': position?.accuracy ?? 0.0,
      'recorded_at': clientSosTimestamp.toIso8601String(),
      'network_status': 'ONLINE',
      'device_status': {
        'source': 'mobile_fast_path',
        'sender_id': _bluetooth.myDeviceId,
        'client_sos_timestamp': clientSosTimestamp.toIso8601String(),
      },
      'is_test': isTest,
      'protocol_version': packet.protocolVersion,
      'hop_count': packet.hopCount,
      'max_hops': packet.maxHops,
    };

    // 3. Encrypted SQLite persistence
    try {
      await _database.queueEmergencyOperation(
        id: '$localId-create',
        localEmergencyId: localId,
        operation: 'CREATE',
        encryptedPayload: _security.encrypt(jsonEncode(payload)),
      );
    } catch (_) {}

    // 4. Start 5-second location updates stream
    try {
      _startLocationUpdates(localId);
    } catch (_) {}

    // 5. Internet dispatch to backend API
    try {
      final response = await _api.post('/emergencies', payload) as Map<String, dynamic>;
      final remoteId = response['id'].toString();
      try {
        await _database.markEmergencyOperationSynced('$localId-create', remoteEmergencyId: remoteId);
      } catch (_) {}
      await _storage.setRemoteEmergencyId(remoteId);
    } on ApiException {
      // Retained in SQLite queue for automatic sync upon reconnection
    } catch (_) {}
  }


  void _startLocationUpdates(String localEmergencyId) {
    if (kIsWeb) return;
    try {
      _locationSubscription?.cancel();
      _locationSubscription = _location.activeEmergencyLocations().listen((position) async {
        if (!isActive) return;
        final remoteId = _storage.activeRemoteEmergencyId;
        final payload = <String, dynamic>{
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
        };
        final queueId = _id('location');
        try {
          await _database.queueEmergencyOperation(
            id: queueId,
            localEmergencyId: localEmergencyId,
            remoteEmergencyId: remoteId,
            operation: 'LOCATION',
            encryptedPayload: _security.encrypt(jsonEncode(payload)),
          );
        } catch (_) {}
        if (remoteId != null) {
          try {
            await _api.post('/emergencies/$remoteId/locations', payload);
            try {
              await _database.markEmergencyOperationSynced(queueId);
            } catch (_) {}
          } on ApiException {
            // Retained in the encrypted queue for a later retry.
          } catch (_) {}
        }
      });
    } catch (_) {}
  }

  Future<void> syncPending() async {
    final pending = await _database.getPendingEmergencyOperations();
    for (final item in pending) {
      final payload = jsonDecode(_security.decrypt(item['encrypted_payload'] as String)) as Map<String, dynamic>;
      final localId = item['local_emergency_id'] as String;
      var remoteId = item['remote_emergency_id'] as String? ?? _storage.activeRemoteEmergencyId;
      try {
        switch (item['operation'] as String) {
          case 'CREATE':
            final response = await _api.post('/emergencies', payload) as Map<String, dynamic>;
            remoteId = response['id'].toString();
            await _database.markEmergencyOperationSynced(item['id'] as String, remoteEmergencyId: remoteId);
            if (_storage.activeLocalEmergencyId == localId) await _storage.setRemoteEmergencyId(remoteId);
            break;
          case 'LOCATION':
            if (remoteId == null) continue;
            await _api.post('/emergencies/$remoteId/locations', payload);
            await _database.markEmergencyOperationSynced(item['id'] as String);
            break;
          case 'CANCEL':
            if (remoteId == null) continue;
            await _api.post('/emergencies/$remoteId/cancel', payload);
            await _database.markEmergencyOperationSynced(item['id'] as String);
            break;
          case 'END':
            if (remoteId == null) continue;
            await _api.post('/emergencies/$remoteId/end');
            await _database.markEmergencyOperationSynced(item['id'] as String);
            break;
        }
      } on ApiException {
        return;
      }
    }
  }

  Future<void> cancelEmergency({String reason = 'USER_CANCELLED'}) async {
    final localId = _storage.activeLocalEmergencyId;
    if (localId == null) return;
    final remoteId = _storage.activeRemoteEmergencyId;
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    await _bluetooth.stopSosAdvertising();
    await AudioAlertService().stopSiren();
    await NotificationService().clearEmergencyActive();

    _stateMachine.transitionTo(EmergencyState.cancelled, reason: reason);

    if (remoteId != null) {
      try {
        await _api.post('/emergencies/$remoteId/cancel', {'reason': reason});
      } on ApiException {
        await _database.queueEmergencyOperation(
          id: _id('cancel'),
          localEmergencyId: localId,
          remoteEmergencyId: remoteId,
          operation: 'CANCEL',
          encryptedPayload: _security.encrypt(jsonEncode({'reason': reason})),
        );
      }
    }
    await _storage.clearActiveEmergency();
    _stateMachine.reset();
  }

  Future<void> endEmergency() async {
    final localId = _storage.activeLocalEmergencyId;
    if (localId == null) return;
    final remoteId = _storage.activeRemoteEmergencyId;
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    await _bluetooth.stopSosAdvertising();
    await NotificationService().clearEmergencyActive();

    _stateMachine.transitionTo(EmergencyState.resolved, reason: 'User marked safe');

    if (remoteId != null) {
      try {
        await _api.post('/emergencies/$remoteId/end');
      } on ApiException {
        await _queueEnd(localId, remoteId);
      }
    } else {
      await _queueEnd(localId, null);
    }
    await _storage.clearActiveEmergency();
    _stateMachine.reset();
  }

  Future<void> _queueEnd(String localId, String? remoteId) => _database.queueEmergencyOperation(
        id: _id('end'),
        localEmergencyId: localId,
        remoteEmergencyId: remoteId,
        operation: 'END',
        encryptedPayload: _security.encrypt('{}'),
      );

  Future<void> setHelperAvailability(bool available) async {
    final position = await _location.getBestAvailableLocation();
    if (position == null) throw const LocationUnavailableException();
    if (available) {
      await _api.patch('/auth/preferences', {
        'emergency_alerts_enabled': true,
        'location_sharing_enabled': true,
      });
      await _bluetooth.startSosScanning();
    } else {
      await _bluetooth.stopSosScanning();
    }
    await _api.put('/helpers/presence', {
      'is_available': available,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<NearbyEmergency>> getNearbyEmergencies() async {
    try {
      final response = await _api.get('/emergencies/nearby') as List<dynamic>;
      return response.map((item) => NearbyEmergency.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> acknowledge(String emergencyId, {bool helping = false}) async {
    try {
      await _api.post(
        '/emergencies/$emergencyId/acknowledge',
        {'response_type': helping ? 'HELPING' : 'ACKNOWLEDGED'},
      );
    } catch (_) {}
  }

  Future<int> responderCount(String emergencyId) async {
    try {
      final response = await _api.get('/emergencies/$emergencyId/responders') as List<dynamic>;
      return response.length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> openOfficialEmergencyDialer({String number = '112'}) async {
    await const MethodChannel('com.bhai.app/ble_emergency').invokeMethod<void>('dialEmergency', {'number': number});
  }

  // --- 5-Second Live Location Sharing Session Management ---

  String? _activeLiveSessionId;
  Timer? _liveLocationTimer;
  Position? _lastLivePosition;
  DateTime? _lastLiveUpdatedAt;

  bool get isLiveLocationActive => _activeLiveSessionId != null;
  String? get activeLiveSessionId => _activeLiveSessionId;
  Position? get lastLivePosition => _lastLivePosition;
  DateTime? get lastLiveUpdatedAt => _lastLiveUpdatedAt;

  Future<String> startLiveLocationSharing() async {
    final position = await _location.getBestAvailableLocation();
    if (position == null) throw const LocationUnavailableException();

    final payload = <String, dynamic>{
      'emergency_id': _storage.activeRemoteEmergencyId,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
    };

    final response = await _api.post('/api/live-location/start', payload) as Map<String, dynamic>;
    final sessionId = response['id'].toString();
    _activeLiveSessionId = sessionId;
    _lastLivePosition = position;
    _lastLiveUpdatedAt = DateTime.now();

    // Start independent 5-second location stream
    _liveLocationTimer?.cancel();
    _liveLocationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _sendPeriodicLiveLocationUpdate();
    });

    return sessionId;
  }

  Future<void> _sendPeriodicLiveLocationUpdate() async {
    final sessionId = _activeLiveSessionId;
    if (sessionId == null) return;
    try {
      final position = await _location.getBestAvailableLocation();
      if (position == null) return;
      _lastLivePosition = position;
      _lastLiveUpdatedAt = DateTime.now();

      await _api.post('/api/live-location/update', {
        'session_id': sessionId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
      });
    } catch (_) {}
  }

  Future<void> stopLiveLocationSharing() async {
    final sessionId = _activeLiveSessionId;
    _liveLocationTimer?.cancel();
    _liveLocationTimer = null;
    _activeLiveSessionId = null;

    if (sessionId != null) {
      try {
        await _api.post('/api/live-location/stop', {'session_id': sessionId});
      } catch (_) {}
    }
  }

  String getNavigationUrl(double latitude, double longitude) {
    return 'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude';
  }

  Future<void> openNavigation(double latitude, double longitude) async {
    try {
      const channel = MethodChannel('com.bhai.app/ble_emergency');
      await channel.invokeMethod('openGoogleMaps', {
        'latitude': latitude,
        'longitude': longitude,
      });
    } catch (e) {
      debugPrint('Error invoking openGoogleMaps: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getNearbyUsers({double? latitude, double? longitude, int radius = 2000}) async {
    double? lat = latitude ?? _lastLivePosition?.latitude;
    double? lon = longitude ?? _lastLivePosition?.longitude;

    if (lat == null || lon == null) {
      final pos = await _location.getBestAvailableLocation();
      if (pos != null) {
        lat = pos.latitude;
        lon = pos.longitude;
      }
    }

    if (lat == null || lon == null) return [];

    try {
      final response = await _api.get('/api/nearby-users?latitude=$lat&longitude=$lon&radius_meters=$radius') as List<dynamic>;
      return response.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

}

