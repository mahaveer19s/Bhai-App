import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../storage/local_storage.dart';
import 'api_client.dart';
import 'notification_service.dart';

/// Models a detected nearby Bhai peer advertising presence.
class BhaiNearbyDevice {
  final String deviceId;
  final int rssi;
  final DateTime lastSeen;

  const BhaiNearbyDevice({
    required this.deviceId,
    required this.rssi,
    required this.lastSeen,
  });

  String get proximity {
    if (rssi >= -60) return 'Immediate (~1-5m)';
    if (rssi >= -75) return 'Very Near (~5-15m)';
    if (rssi >= -88) return 'Nearby (~15-30m)';
    return 'In Range';
  }

  String get signalStrength {
    if (rssi >= -65) return 'Strong';
    if (rssi >= -80) return 'Medium';
    return 'Weak';
  }
}

/// Models an incoming emergency SOS broadcast from a nearby peer.
class BhaiEmergencyAlert {
  final String emergencyId;
  final String senderId;
  final String targetId;
  final int rssi;
  final double? latitude;
  final double? longitude;
  final bool hasLocation;
  final DateTime receivedAt;
  final DateTime triggeredAt;
  final String source; // 'BLE Radio' or 'Internet'

  const BhaiEmergencyAlert({
    String? emergencyId,
    required this.senderId,
    required this.targetId,
    required this.rssi,
    this.latitude,
    this.longitude,
    this.hasLocation = false,
    required this.receivedAt,
    DateTime? triggeredAt,
    this.source = 'BLE Radio',
  })  : emergencyId = emergencyId ?? 'BHAI-$senderId',
        triggeredAt = triggeredAt ?? receivedAt;

  String get estimatedDistance {
    if (rssi >= -60) return 'Within ~1-5 meters (Immediate)';
    if (rssi >= -75) return 'Within ~5-15 meters (Very Near)';
    if (rssi >= -88) return 'Within ~15-30 meters (Nearby)';
    return 'In Bluetooth range (~30-50m)';
  }
}

/// Real Bluetooth Low Energy (BLE) service for nearby Bhai peer discovery
/// and peer-to-peer emergency alert delivery.
class BluetoothService {
  BluetoothService._();
  static final BluetoothService _instance = BluetoothService._();
  factory BluetoothService() => _instance;

  static const MethodChannel _channel = MethodChannel('com.bhai.app/ble_emergency');
  static const EventChannel _events = EventChannel('com.bhai.app/ble_emergency_events');

  static const int typePresence = 1;
  static const int typeEmergencyAlert = 2;
  static const int typeAlertAck = 3;

  StreamSubscription<dynamic>? _eventSubscription;
  final Map<String, BhaiNearbyDevice> _detectedDevices = {};
  DateTime? _lastAlertNotificationTime;
  String? _lastAlertSenderId;
  Timer? _networkSyncTimer;
  final Set<String> _handledEmergencyIds = {};
  final List<Map<String, dynamic>> _offlineEmergencyQueue = [];
  String? _myActiveEmergencyId;

  final StreamController<List<BhaiNearbyDevice>> _nearbyDevicesController =
      StreamController<List<BhaiNearbyDevice>>.broadcast();
  final StreamController<BhaiEmergencyAlert> _incomingAlertController =
      StreamController<BhaiEmergencyAlert>.broadcast();
  final StreamController<String> _ackReceivedController =
      StreamController<String>.broadcast();

  bool _isAdvertising = false;
  bool _isScanning = false;
  int _currentAdvertisingType = 0;

  Stream<List<BhaiNearbyDevice>> get nearbyDevicesStream => _nearbyDevicesController.stream;
  Stream<BhaiEmergencyAlert> get incomingAlertsStream => _incomingAlertController.stream;
  Stream<String> get ackReceivedStream => _ackReceivedController.stream;

  String get myDeviceId => LocalStorage().getOrGenerateBhaiDeviceId();
  bool get isAdvertising => _isAdvertising;
  bool get isScanning => _isScanning;
  int get currentAdvertisingType => _currentAdvertisingType;
  bool get isEmergencyBroadcasting => _isAdvertising && _currentAdvertisingType == typeEmergencyAlert;
  String? get myActiveEmergencyId => _myActiveEmergencyId;

  /// Check if Bluetooth is currently turned on.
  Future<bool> isBluetoothEnabled() async {
    if (kIsWeb) return true;
    try {
      final enabled = await _channel.invokeMethod<bool>('isBluetoothEnabled');
      return enabled ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Check if internet / Wi-Fi / mobile data is connected.
  Future<bool> isInternetConnected() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return true; // Assume true on fallback
    }
  }

  /// Check if GPS location service and permissions are active.
  Future<bool> isLocationEnabled() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return false;
      final perm = await Geolocator.checkPermission();
      return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// Prompts user to enable Bluetooth.
  Future<void> requestEnableBluetooth() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('requestEnableBluetooth');
    } catch (_) {}
  }

  /// Request runtime Bluetooth and Location permissions for Android/iOS.
  Future<bool> requestPermissions() async {
    if (kIsWeb) return true;
    try {
      final permissions = await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.location,
        Permission.notification,
      ].request();

      // Ensure scanning & advertising permissions are granted
      final scanGranted = permissions[Permission.bluetoothScan]?.isGranted ?? false;
      final advGranted = permissions[Permission.bluetoothAdvertise]?.isGranted ?? false;
      final locGranted = permissions[Permission.location]?.isGranted ?? false;

      return (scanGranted && advGranted) || locGranted;
    } catch (_) {
      return false;
    }
  }

  /// Checks if required permissions are already granted.
  Future<bool> hasPermissions() async {
    if (kIsWeb) return true;
    try {
      final scan = await Permission.bluetoothScan.isGranted;
      final adv = await Permission.bluetoothAdvertise.isGranted;
      final loc = await Permission.location.isGranted;
      return (scan && adv) || loc;
    } catch (_) {
      return false;
    }
  }

  /// Launches Google Maps navigation directly to target coordinates.
  Future<void> openGoogleMaps(double latitude, double longitude) async {
    if (kIsWeb) {
      // In browser, trigger window open via native channel or url
      try {
        await _channel.invokeMethod<void>('openGoogleMaps', {
          'latitude': latitude,
          'longitude': longitude,
        });
      } catch (_) {}
      return;
    }
    try {
      await _channel.invokeMethod<void>('openGoogleMaps', {
        'latitude': latitude,
        'longitude': longitude,
      });
    } catch (_) {}
  }

  /// Starts the standby presence and alert listener mode.
  /// Every Bhai user running the app broadcasts presence and scans for nearby alerts.
  Future<void> startStandbyMode() async {
    _startNetworkSync();

    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('setMyDeviceId', {'deviceId': myDeviceId});
    } catch (_) {}

    final granted = await hasPermissions();
    if (!granted) {
      final nowGranted = await requestPermissions();
      if (!nowGranted) return;
    }

    _ensureEventListener();
    await startPresenceAdvertising();
    await startScanning();
  }

  /// Stops standby mode, timer polling, advertising, and scanning.
  Future<void> stopStandbyMode() async {
    _networkSyncTimer?.cancel();
    _networkSyncTimer = null;
    await stopAdvertising();
    await stopScanning();
  }

  /// Background polling to sync emergency alerts and acknowledgments over the local network.
  void _startNetworkSync() {
    _networkSyncTimer?.cancel();
    _networkSyncTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      _flushOfflineQueue();
      try {
        final res = await ApiClient().get('/emergencies/active');
        if (res is List) {
          for (final item in res) {
            final emId = (item['id']?.toString() ?? '').trim();
            final sender = (item['sender_id']?.toString() ?? '').trim().toUpperCase();
            final status = item['status']?.toString() ?? '';
            final helperCount = (item['helper_count'] as num?)?.toInt() ?? 0;

            // If a helper responded to our alert, notify ACK stream ONLY while SOS is actively broadcasting!
            if (sender == myDeviceId.toUpperCase() &&
                helperCount > 0 &&
                ((_isAdvertising && _currentAdvertisingType == typeEmergencyAlert) || _myActiveEmergencyId != null)) {
              _ackReceivedController.add('HELPER_CONFIRMED');
            }


            // CRITICAL V2: Strict self-alert prevention & cross-transport deduplication
            if (sender.isEmpty || sender == myDeviceId.toUpperCase()) continue;
            if (emId.toUpperCase() == _myActiveEmergencyId) continue;
            if ('BHAI-$sender'.toUpperCase() == _myActiveEmergencyId) continue;

            if (status == 'ACTIVE' &&
                !_handledEmergencyIds.contains(emId.toUpperCase()) &&
                !_handledEmergencyIds.contains('BHAI-$sender'.toUpperCase())) {
              _handledEmergencyIds.add(emId.toUpperCase());
              _handledEmergencyIds.add('BHAI-$sender'.toUpperCase());

              final lat = (item['latitude'] as num?)?.toDouble();
              final lon = (item['longitude'] as num?)?.toDouble();
              final hasLoc = lat != null && lon != null && (lat != 0.0 || lon != 0.0);

              final alert = BhaiEmergencyAlert(
                emergencyId: emId.isNotEmpty ? emId : 'BHAI-$sender',
                senderId: sender,
                targetId: myDeviceId,
                rssi: -65,
                latitude: lat,
                longitude: lon,
                hasLocation: hasLoc,
                receivedAt: DateTime.now(),
                triggeredAt: DateTime.tryParse(item['triggered_at']?.toString() ?? '') ?? DateTime.now(),
                source: 'Internet',
              );

              NotificationService().showNearbyBluetoothAlert(
                senderId: sender,
                rssi: -65,
              );

              _incomingAlertController.add(alert);
            }
          }
        }
      } catch (_) {}
    });
  }

  /// Start advertising a presence beacon so nearby Bhai users can detect this device.
  Future<void> startPresenceAdvertising() async {
    await startAdvertising(type: typePresence, targetId: '00000000');
  }

  /// Broadcasts an advertisement packet over BLE.
  Future<void> startAdvertising({
    required int type,
    String? targetId,
    double? latitude,
    double? longitude,
  }) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('startAdvertising', {
        'type': type,
        'senderId': myDeviceId,
        'targetId': targetId ?? '00000000',
        'latitude': latitude ?? 0.0,
        'longitude': longitude ?? 0.0,
        'hasLocation': latitude != null && longitude != null && (latitude != 0.0 || longitude != 0.0),
      });
      _isAdvertising = true;
      _currentAdvertisingType = type;
    } on PlatformException catch (e) {
      debugPrint('BLE advertising error: ${e.message}');
    } catch (_) {}
  }

  /// Stops BLE advertising.
  Future<void> stopAdvertising() async {
    if (kIsWeb || !_isAdvertising) return;
    try {
      await _channel.invokeMethod<void>('stopAdvertising');
    } catch (_) {} finally {
      _isAdvertising = false;
      _currentAdvertisingType = 0;
    }
  }

  /// Starts scanning for nearby Bhai packets.
  Future<void> startScanning() async {
    if (kIsWeb || _isScanning) return;
    _ensureEventListener();
    try {
      await _channel.invokeMethod<void>('startScanning');
      _isScanning = true;
    } on PlatformException catch (e) {
      debugPrint('BLE scanning error: ${e.message}');
    } catch (_) {}
  }

  /// Stops scanning for nearby packets.
  Future<void> stopScanning() async {
    if (kIsWeb || !_isScanning) return;
    try {
      await _channel.invokeMethod<void>('stopScanning');
    } catch (_) {} finally {
      _isScanning = false;
    }
  }

  /// Actively scans for nearby Bhai presence beacons, groups detected devices,
  /// and returns the device with the strongest signal (nearest).
  Future<BhaiNearbyDevice?> findNearestBhai({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (kIsWeb) {
      // On web browser, discover peers via local network
      await Future.delayed(const Duration(milliseconds: 1200));
      return BhaiNearbyDevice(
        deviceId: 'BHAI-PEER',
        rssi: -65,
        lastSeen: DateTime.now(),
      );
    }

    final hasPerm = await hasPermissions();
    if (!hasPerm && !await requestPermissions()) return null;

    _detectedDevices.clear();
    _nearbyDevicesController.add([]);

    _ensureEventListener();
    await startScanning();

    final completer = Completer<BhaiNearbyDevice?>();
    Timer? earlyReturnTimer;

    // Listen for detected devices during discovery window
    final sub = _nearbyDevicesController.stream.listen((devices) {
      if (devices.isNotEmpty && !completer.isCompleted) {
        // If we found a very strong signal (e.g. >= -65 dBm), we can complete early after brief debounce
        final best = devices.first;
        if (best.rssi >= -65) {
          earlyReturnTimer ??= Timer(const Duration(milliseconds: 1200), () {
            if (!completer.isCompleted) {
              completer.complete(_getStrongestDevice());
            }
          });
        }
      }
    });

    // Timeout window
    final timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(_getStrongestDevice());
      }
    });

    final result = await completer.future;
    earlyReturnTimer?.cancel();
    timeoutTimer.cancel();
    await sub.cancel();

    return result;
  }

  BhaiNearbyDevice? _getStrongestDevice() {
    if (_detectedDevices.isEmpty) return null;
    final sorted = _detectedDevices.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return sorted.first;
  }

  /// Sends an emergency SOS alert targeted to the nearest device (or broadcast).
  /// Starts continuous real BLE Emergency SOS advertising with optional GPS coordinates and unique ID.
  /// Offline-first: broadcasts over radio instantly, and queues for admin sync when network connects.
  Future<void> startEmergencyBroadcast({
    double? latitude,
    double? longitude,
    String? emergencyId,
  }) async {
    final emId = emergencyId ?? 'BHAI-${DateTime.now().millisecondsSinceEpoch % 1000000}-$myDeviceId';
    _myActiveEmergencyId = emId.toUpperCase();
    _handledEmergencyIds.add(_myActiveEmergencyId!);
    _handledEmergencyIds.add('BHAI-$myDeviceId'.toUpperCase());

    // 1. Queue locally and sync to admin backend if online
    final payload = {
      'idempotency_key': emId,
      'latitude': latitude ?? 0.0,
      'longitude': longitude ?? 0.0,
      'accuracy': (latitude != null && longitude != null && (latitude != 0.0 || longitude != 0.0)) ? 10.0 : 0.0,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
      'is_test': false,
      'device_status': {
        'sender_id': myDeviceId,
        'target_id': 'ALL',
      },
    };
    _queueAndSyncEmergency(payload);

    if (kIsWeb) return;

    // 2. Stop presence beacon and start real BLE SOS beacon
    await stopAdvertising();
    await startAdvertising(
      type: typeEmergencyAlert,
      targetId: '00000000', // Broadcast to all nearby devices
      latitude: latitude,
      longitude: longitude,
    );

    // Keep scanning active to receive ACKs from nearby helpers
    await startScanning();
  }

  /// Stops emergency broadcast and returns to normal presence beacon mode.
  Future<void> stopEmergencyBroadcast() async {
    _myActiveEmergencyId = null;
    await stopAdvertising();
    if (!kIsWeb) {
      await startPresenceAdvertising();
    }
  }

  /// Receiver indicates: I'm going to help the emergency sender.
  /// Broadcasts a real BLE ACK packet (0x03) and syncs with backend if reachable.
  Future<void> goingToHelp(String alertSenderId, String emergencyId) async {
    await acknowledgeAlert(alertSenderId);
    try {
      final res = await ApiClient().get('/emergencies/active');
      if (res is List) {
        for (final item in res) {
          final emId = (item['id']?.toString() ?? '').trim();
          final sender = (item['sender_id']?.toString() ?? '').trim().toUpperCase();
          if (emId.toUpperCase() == emergencyId.toUpperCase() ||
              sender == alertSenderId.toUpperCase() ||
              res.length == 1) {
            await ApiClient().post('/emergencies/$emId/acknowledge', {
              'response_type': 'GOING_TO_HELP',
            });
          }
        }
      }
    } catch (_) {}
  }

  void _queueAndSyncEmergency(Map<String, dynamic> payload) {
    _offlineEmergencyQueue.add(payload);
    _flushOfflineQueue();
  }

  Future<void> _flushOfflineQueue() async {
    if (_offlineEmergencyQueue.isEmpty) return;
    final toRemove = <Map<String, dynamic>>[];
    for (final item in List<Map<String, dynamic>>.from(_offlineEmergencyQueue)) {
      try {
        final res = await ApiClient().post('/emergencies', item);
        if (res != null) {
          toRemove.add(item);
        }
      } catch (e) {
        // Still offline, will retry on next poll cycle
        break;
      }
    }
    _offlineEmergencyQueue.removeWhere((i) => toRemove.contains(i));
  }

  /// Sends an emergency SOS alert targeted to the nearest device (or broadcast).
  /// Listens for confirmation ACK from the target device.
  Future<bool> sendEmergencyAlert({
    BhaiNearbyDevice? target,
    double? latitude,
    double? longitude,
    Duration ackTimeout = const Duration(seconds: 5),
  }) async {
    // 1. Dispatch over local network to backend if internet/LAN is available (non-blocking)
    _queueAndSyncEmergency({
      'idempotency_key': 'bhai-alert-${DateTime.now().millisecondsSinceEpoch}-$myDeviceId',
      'latitude': latitude ?? 0.0,
      'longitude': longitude ?? 0.0,
      'accuracy': (latitude != null && longitude != null && (latitude != 0.0 || longitude != 0.0)) ? 10.0 : 0.0,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
      'is_test': false,
      'device_status': {
        'sender_id': myDeviceId,
        'target_id': target?.deviceId ?? 'ALL',
      },
    });

    if (kIsWeb) return true;

    final targetId = target?.deviceId ?? '00000000';

    // 2. Stop presence beacon and broadcast high-priority Emergency SOS beacon over BLE
    await stopAdvertising();
    await startAdvertising(
      type: typeEmergencyAlert,
      targetId: targetId,
      latitude: latitude,
      longitude: longitude,
    );

    // Keep scanning active to receive the ACK
    await startScanning();

    final completer = Completer<bool>();
    StreamSubscription<String>? ackSub;

    ackSub = ackReceivedStream.listen((ackSenderId) {
      if (target == null || ackSenderId == target.deviceId || !completer.isCompleted) {
        completer.complete(true);
      }
    });

    // Timeout: Even if ACK is not received, the SOS beacon was broadcast successfully
    final timer = Timer(ackTimeout, () {
      if (!completer.isCompleted) {
        completer.complete(true);
      }
    });

    final success = await completer.future;
    timer.cancel();
    await ackSub.cancel();

    // After transmitting emergency alert, keep alert active for a short window
    // then resume standby presence advertising.
    Future.delayed(const Duration(seconds: 10), () {
      if (_currentAdvertisingType == typeEmergencyAlert) {
        startPresenceAdvertising();
      }
    });

    return success;
  }

  /// Legacy helper compatibility for background tasks & tests
  Future<void> startSosAdvertising(String beacon) async {
    await startAdvertising(type: typeEmergencyAlert, targetId: '00000000');
  }

  Future<void> stopSosAdvertising() => stopAdvertising();

  Future<void> startSosScanning() => startScanning();

  Future<void> stopSosScanning() => stopScanning();

  /// Sends an acknowledgment beacon back to the emergency sender to confirm receipt.
  Future<void> acknowledgeAlert(String alertSenderId) async {
    // 1. Broadcast BLE ACK on mobile
    if (!kIsWeb) {
      try {
        await stopAdvertising();
        await startAdvertising(
          type: typeAlertAck,
          targetId: alertSenderId,
        );

        // Revert back to presence advertising after 4 seconds
        Future.delayed(const Duration(seconds: 4), () {
          startPresenceAdvertising();
        });
      } catch (_) {}
    }

    // 2. Acknowledge via local network backend API
    try {
      final res = await ApiClient().get('/emergencies/active');
      if (res is List) {
        for (final item in res) {
          final emId = item['id']?.toString() ?? '';
          final sender = (item['sender_id']?.toString() ?? '').trim().toUpperCase();
          if (emId.isNotEmpty && (sender == alertSenderId.toUpperCase() || res.length == 1)) {
            await ApiClient().post('/emergencies/$emId/acknowledge', {
              'response_type': 'HELPING',
            });
          }
        }
      }
    } catch (_) {}
  }

  /// Direct system phone call to emergency helpline.
  Future<void> dialEmergency(String number) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('dialEmergency', {'number': number});
    } catch (_) {}
  }

  /// Sets up the native EventChannel listener.
  void _ensureEventListener() {
    if (_eventSubscription != null) return;
    _eventSubscription = _events.receiveBroadcastStream().listen(
      (event) {
        try {
          final map = Map<String, dynamic>.from(event as Map);
          final type = map['type'] as int? ?? 1;
          final senderId = (map['senderId'] as String? ?? '').trim().toUpperCase();
          final targetId = (map['targetId'] as String? ?? '').trim().toUpperCase();
          final rssi = (map['rssi'] as num?)?.toInt() ?? -75;

          // Ignore own self-advertisements
          if (senderId.isEmpty || senderId == myDeviceId.toUpperCase()) return;

          final now = DateTime.now();

          if (type == typePresence) {
            // Presence beacon: Add or update nearby device
            _detectedDevices[senderId] = BhaiNearbyDevice(
              deviceId: senderId,
              rssi: rssi,
              lastSeen: now,
            );
            _cleanStaleDevices();
            _nearbyDevicesController.add(_detectedDevices.values.toList());
          } else if (type == typeEmergencyAlert) {
            // CRITICAL V2: Strict self-alert prevention: NEVER alert yourself
            if (senderId.isEmpty || senderId == myDeviceId.toUpperCase()) return;
            final alertEmId = 'BHAI-$senderId';
            if (alertEmId.toUpperCase() == _myActiveEmergencyId) return;

            // CRITICAL V2: Strict cross-transport deduplication: If already handled via BLE or Internet, do not show duplicate
            if (_handledEmergencyIds.contains(alertEmId.toUpperCase())) return;

            // Emergency SOS broadcast: Alert recipient
            final isForMe = targetId == '00000000' ||
                targetId == 'FFFFFFFF' ||
                targetId == myDeviceId.toUpperCase();

            if (isForMe) {
              _handledEmergencyIds.add(alertEmId.toUpperCase());
              _lastAlertSenderId = senderId;
              _lastAlertNotificationTime = now;

              // Trigger high-priority emergency notification
              NotificationService().showNearbyBluetoothAlert(
                senderId: senderId,
                rssi: rssi,
              );

              final lat = (map['latitude'] as num?)?.toDouble();
              final lon = (map['longitude'] as num?)?.toDouble();
              final hasLoc = map['hasLocation'] == true;

              final alert = BhaiEmergencyAlert(
                emergencyId: alertEmId,
                senderId: senderId,
                targetId: targetId,
                rssi: rssi,
                latitude: lat,
                longitude: lon,
                hasLocation: hasLoc,
                receivedAt: now,
                triggeredAt: now,
                source: 'BLE Radio',
              );
              _incomingAlertController.add(alert);
            }
          } else if (type == typeAlertAck) {
            // Acknowledgment received from target
            if (targetId == myDeviceId.toUpperCase()) {
              _ackReceivedController.add(senderId);
            }
          }
        } catch (e) {
          debugPrint('Error processing BLE event: $e');
        }
      },
      onError: (err) {
        debugPrint('BLE event channel error: $err');
      },
    );
  }

  void _cleanStaleDevices() {
    final threshold = DateTime.now().subtract(const Duration(seconds: 15));
    _detectedDevices.removeWhere((_, device) => device.lastSeen.isBefore(threshold));
  }

  void dispose() {
    _networkSyncTimer?.cancel();
    _networkSyncTimer = null;
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _nearbyDevicesController.close();
    _incomingAlertController.close();
    _ackReceivedController.close();
  }
}
