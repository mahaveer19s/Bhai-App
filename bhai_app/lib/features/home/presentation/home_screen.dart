import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/services/bluetooth_service.dart';
import '../../../../core/services/emergency_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../chat/presentation/bluetooth_mesh_chat_dialog.dart';
import '../../emergency/presentation/emergency_received_dialog.dart';




class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final BluetoothService _bluetooth = BluetoothService();
  final EmergencyService _emergencyService = EmergencyService();

  bool _isBluetoothOn = true;
  bool _isInternetOn = true;
  bool _isLocationOn = true;
  bool _hasPermissions = true;
  bool _isBroadcastingSos = false;
  bool _isActivating = false;
  bool _isLiveLocationSharing = false;
  bool _isLoadingNearby = false;
  String? _liveSessionId;
  Position? _currentPosition;
  String? _emergencyId;
  String _statusMessage = 'Standby • Ready to broadcast or detect nearby emergency alerts';
  String? _acknowledgedHelperId;

  StreamSubscription<BhaiEmergencyAlert>? _incomingAlertSub;
  StreamSubscription<String>? _ackSub;
  Timer? _statusCheckTimer;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  bool _isAlertOpen = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkHardwareStatus();
    _initStandby();

    // Periodically refresh Bluetooth, Internet, and Location states
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkHardwareStatus();
    });
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    _incomingAlertSub?.cancel();
    _ackSub?.cancel();
    _pulseController.dispose();
    _bluetooth.stopStandbyMode();
    if (_isLiveLocationSharing) {
      _emergencyService.stopLiveLocationSharing();
    }
    super.dispose();
  }

  Future<void> _checkHardwareStatus() async {
    final bt = await _bluetooth.isBluetoothEnabled();
    final perm = await _bluetooth.hasPermissions();
    final net = await _bluetooth.isInternetConnected();
    final loc = await _bluetooth.isLocationEnabled();
    if (mounted) {
      setState(() {
        _isBluetoothOn = bt;
        _hasPermissions = perm;
        _isInternetOn = net;
        _isLocationOn = loc;
      });
    }
  }

  Future<void> _initStandby() async {
    // Start background presence and incoming alert listener
    await _bluetooth.startStandbyMode();

    _incomingAlertSub = _bluetooth.incomingAlertsStream.listen((alert) {
      if (!_isAlertOpen && mounted) {
        _isAlertOpen = true;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => EmergencyReceivedDialog(alert: alert),
        ).then((_) {
          _isAlertOpen = false;
        });
      }
    });

    _ackSub = _bluetooth.ackReceivedStream.listen((helperSenderId) {
      if (mounted && _isBroadcastingSos) {
        setState(() {
          _acknowledgedHelperId = helperSenderId;
          _statusMessage = 'Helper BHAI-$helperSenderId confirmed: I AM COMING! 🏃';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("🚨 Nearby Bhai Helper (BHAI-$helperSenderId) confirmed: I'M COMING!"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    });

  }

  Future<void> _onBhaiHelpPressed() async {
    if (_isBroadcastingSos) {
      _confirmStopBroadcast();
      return;
    }

    // 1. Fast Path: Immediate Local UI State Update (<50ms)
    setState(() {
      _isBroadcastingSos = true;
      _isActivating = false;
      _isLiveLocationSharing = true;
      _statusMessage = '🚨 EMERGENCY BROADCAST ACTIVE • BLE + 5s Live Location Stream';
    });

    try {
      final snapshot = await _emergencyService.activateFast();
      if (mounted) {
        setState(() {
          _emergencyId = snapshot.remoteId ?? snapshot.localId;
        });
      }
    } catch (e) {
      debugPrint('Fast SOS activation: $e');
    }
  }

  Future<void> _stopEmergencyBroadcast() async {
    // 1. Immediate Synchronous Local UI Reset (<5ms)
    setState(() {
      _isBroadcastingSos = false;
      _isActivating = false;
      _isLiveLocationSharing = false;
      _liveSessionId = null;
      _acknowledgedHelperId = null;
      _statusMessage = 'Standby • Ready to broadcast or detect nearby emergency alerts';
    });

    // 2. Synchronous Local Resource Teardown & Async Server Synchronization
    await _emergencyService.stopEmergencyFast(reason: 'STOPPED_BY_USER');
  }

  Future<void> _toggleLiveLocationStream() async {
    if (_isLiveLocationSharing) {
      setState(() {
        _isLiveLocationSharing = false;
        _liveSessionId = null;
        if (!_isBroadcastingSos) {
          _statusMessage = 'Standby • Live location sharing stopped';
        }
      });
      await _emergencyService.stopLiveLocationSharing();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Live location stream stopped'),
          backgroundColor: Colors.blueGrey,
        ),
      );
    } else {
      setState(() {
        _statusMessage = 'Acquiring GPS location...';
      });
      try {
        final sid = await _emergencyService.startLiveLocationSharing();
        if (!mounted) return;
        setState(() {
          _isLiveLocationSharing = true;
          _liveSessionId = sid;
          _statusMessage = '🟢 Live location streaming active (updates every ~5s)';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🟢 Live location sharing active (transmitting first fix immediately)'),
            backgroundColor: Colors.teal,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start live stream: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _openNavigation([double? lat, double? lon]) {
    final targetLat = lat ?? _currentPosition?.latitude ?? 28.6273;
    final targetLon = lon ?? _currentPosition?.longitude ?? 77.3725;
    if (targetLat == 0.0 && targetLon == 0.0) return;
    _emergencyService.openNavigation(targetLat, targetLon);
  }

  void _shareLocationLink([double? lat, double? lon]) {
    final targetLat = lat ?? _currentPosition?.latitude ?? 28.6273;
    final targetLon = lon ?? _currentPosition?.longitude ?? 77.3725;
    if (targetLat == 0.0 && targetLon == 0.0) return;
    final text = _emergencyService.getSafeLocationShareText(targetLat, targetLon);
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📍 Safe Location & Navigation Link copied to clipboard!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _findNearbyBhai() async {
    setState(() {
      _isLoadingNearby = true;
    });

    try {
      // 1. Concurrently trigger BLE scanning & GPS backend discovery
      _bluetooth.startScanning();
      final gpsUsersFuture = _emergencyService.getNearbyUsers(
        latitude: _currentPosition?.latitude,
        longitude: _currentPosition?.longitude,
      );

      // Discovery window for BLE peers and GPS backend
      final bleDevices = await _bluetooth.getDiscoveredBhaiDevices(timeout: const Duration(milliseconds: 1400));
      final gpsUsers = await gpsUsersFuture;

      // 2. Merge and deduplicate GPS and BLE results
      final Map<String, Map<String, dynamic>> unified = {};

      for (final u in gpsUsers) {
        final uid = (u['user_id']?.toString() ?? '').trim().toUpperCase();
        if (uid.isEmpty) continue;
        unified[uid] = {
          'id': uid,
          'displayName': u['display_name'] ?? 'Bhai User ${uid.substring(0, uid.length.clamp(0, 6))}',
          'distanceMeters': (u['distance_meters'] as num?)?.round(),
          'latitude': (u['latitude'] as num?)?.toDouble(),
          'longitude': (u['longitude'] as num?)?.toDouble(),
          'isGps': true,
          'isBle': false,
          'bleProximity': null,
          'bleRssi': null,
        };
      }

      // Merge active BLE peers
      for (final bleDevice in bleDevices) {
        final bid = bleDevice.deviceId.toUpperCase();
        if (unified.containsKey(bid)) {
          unified[bid]!['isBle'] = true;
          unified[bid]!['bleProximity'] = bleDevice.proximity;
          unified[bid]!['bleRssi'] = bleDevice.rssi;
        } else {
          unified[bid] = {
            'id': bid,
            'displayName': 'Bhai Peer $bid',
            'distanceMeters': null,
            'latitude': null,
            'longitude': null,
            'isGps': false,
            'isBle': true,
            'bleProximity': bleDevice.proximity,
            'bleRssi': bleDevice.rssi,
          };
        }
      }

      final resultsList = unified.values.toList();

      if (!mounted) return;
      setState(() {
        _isLoadingNearby = false;
      });
      _showNearbyUsersSheet(resultsList);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingNearby = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error scanning for nearby users: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showNearbyUsersSheet(List<Map<String, dynamic>> users) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.radar, color: Colors.cyanAccent, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Nearby Bhai Users (${users.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (users.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  alignment: Alignment.center,
                  child: const Column(
                    children: [
                      Icon(Icons.person_search, color: Colors.grey, size: 48),
                      SizedBox(height: 10),
                      Text(
                        'No active Bhai users detected nearby via GPS or Bluetooth.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: users.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                    itemBuilder: (context, idx) {
                      final u = users[idx];
                      final id = u['id']?.toString() ?? 'User';
                      final name = u['displayName']?.toString() ?? 'Bhai User';
                      final dist = u['distanceMeters'] as int?;
                      final isGps = u['isGps'] == true;
                      final isBle = u['isBle'] == true;
                      final uLat = u['latitude'] as double?;
                      final uLon = u['longitude'] as double?;

                      String transportBadge;
                      Color badgeColor;
                      if (isGps && isBle) {
                        transportBadge = '🌐 + 📡 Dual';
                        badgeColor = Colors.cyanAccent;
                      } else if (isGps) {
                        transportBadge = '🌐 GPS';
                        badgeColor = Colors.blueAccent;
                      } else {
                        transportBadge = '📡 Bluetooth Direct';
                        badgeColor = Colors.greenAccent;
                      }

                      String distanceText;
                      if (dist != null) {
                        distanceText = dist < 1000 ? '${dist}m away' : '${(dist / 1000).toStringAsFixed(1)}km away';
                      } else if (u['bleProximity'] != null) {
                        distanceText = u['bleProximity'].toString();
                      } else {
                        distanceText = 'Nearby';
                      }

                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: badgeColor.withOpacity(0.15),
                              child: Icon(Icons.person_pin_circle, color: badgeColor),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        distanceText,
                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: badgeColor.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: badgeColor.withOpacity(0.4)),
                                        ),
                                        child: Text(
                                          transportBadge,
                                          style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Action buttons: Chat, Navigate, I'm Coming
                            IconButton(
                              icon: const Icon(Icons.chat, color: Colors.cyanAccent, size: 20),
                              tooltip: 'Chat with User',
                              onPressed: () {
                                Navigator.pop(ctx);
                                showDialog<void>(
                                  context: context,
                                  builder: (_) => BluetoothMeshChatDialog(helperId: id),
                                );
                              },
                            ),
                            if (uLat != null && uLon != null)
                              IconButton(
                                icon: const Icon(Icons.directions, color: Colors.greenAccent, size: 20),
                                tooltip: 'Navigate',
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _openNavigation(uLat, uLon);
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }


  void _confirmStopBroadcast() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Stop Emergency Broadcast?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you safe? This will cease the continuous BLE SOS beacon to nearby devices.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentCrimson,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _stopEmergencyBroadcast();
            },
            child: const Text('STOP SOS', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617), // Deep slate black
      appBar: AppBar(
        title: const Text(
          'BHAI',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
            fontSize: 24,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth_audio, color: Color(0xFF38BDF8)),
            tooltip: 'Offline Bluetooth Mesh Chat',
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (_) => const BluetoothMeshChatDialog(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Check Status',
            onPressed: () {
              _checkHardwareStatus();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Status refreshed'), duration: Duration(seconds: 1)),
              );
            },
          ),
        ],

      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Device ID Pill
              _deviceInfoBadge(),
              const SizedBox(height: 14),

              // V2 Core Status Indicators: Bluetooth, Internet, Location
              _v2StatusIndicatorsRow(),
              const SizedBox(height: 16),

              // Bluetooth Warning Banner if OFF
              if (!_isBluetoothOn) ...[
                _bluetoothOffBanner(),
                const SizedBox(height: 16),
              ] else if (!_hasPermissions) ...[
                _permissionMissingBanner(),
                const SizedBox(height: 16),
              ],

              // Big Header & Subtitle
              const Text(
                'EMERGENCY NEARBY ALERT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isBroadcastingSos
                    ? 'Transmitting real BLE Emergency SOS to nearby phones'
                    : 'Tap the button below in an emergency to alert nearby Bhai users.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isBroadcastingSos ? const Color(0xFFFCA5A5) : const Color(0xFF94A3B8),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),

              // Large Central SOS Button
              _centralEmergencyButton(),
              const SizedBox(height: 24),

              // Live Status Card
              _statusCard(),
              const SizedBox(height: 16),

              // If live location stream active, show dedicated live stream card
              if (_isLiveLocationSharing) ...[
                _liveLocationActiveCard(),
                const SizedBox(height: 16),
              ],

              // If broadcasting, show active broadcast details card with Stop button
              if (_isBroadcastingSos) ...[
                _activeBroadcastCard(),
                const SizedBox(height: 16),
              ],

              // Prominent Realtime Location Card with Direct Navigation Arrow
              _liveLocationDisplayCard(),
              const SizedBox(height: 16),

              // Quick Actions: Find Nearby Bhai, Share Live Location, Google Maps Route, Share Link
              _actionButtonsGrid(),
              const SizedBox(height: 20),

              // Footnote: Offline BLE & Dual Transport clarification
              const Text(
                'Dual-Rail Safety: Direct peer-to-peer BLE (2.4GHz) + Internet sync.\nWorks 100% offline between nearby phones without internet or servers.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deviceInfoBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _isBluetoothOn ? Colors.greenAccent : Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Your ID: BHAI-${_bluetooth.myDeviceId}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
          ),
          const SizedBox(width: 10),
          Icon(
            Icons.bluetooth,
            size: 13,
            color: _isBluetoothOn ? Colors.cyanAccent : Colors.redAccent,
          ),
          const SizedBox(width: 4),
          Text(
            _isBluetoothOn ? 'BLE Ready' : 'BT Disabled',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _isBluetoothOn ? Colors.cyanAccent : Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _v2StatusIndicatorsRow() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statusPill(
            'Bluetooth',
            _isBluetoothOn ? 'CONNECTED' : 'OFF',
            _isBluetoothOn ? Colors.greenAccent : Colors.redAccent,
            Icons.bluetooth,
          ),
          Container(width: 1, height: 28, color: Colors.white10),
          _statusPill(
            'Internet',
            _isInternetOn ? 'CONNECTED' : 'OFF',
            _isInternetOn ? Colors.greenAccent : Colors.amberAccent,
            Icons.wifi,
          ),
          Container(width: 1, height: 28, color: Colors.white10),
          _statusPill(
            'Location',
            _isLocationOn ? 'AVAILABLE' : 'UNAVAILABLE',
            _isLocationOn ? Colors.greenAccent : Colors.redAccent,
            Icons.location_on,
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String title, String value, Color color, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _bluetoothOffBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x28EF4444),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent, width: 1.5),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bluetooth_disabled, color: Colors.redAccent, size: 22),
              SizedBox(width: 8),
              Text(
                'Bluetooth is Turned OFF',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Nearby emergency alerts require Bluetooth. Please turn on Bluetooth.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            icon: const Icon(Icons.bluetooth, size: 18),
            label: const Text('TURN ON BLUETOOTH', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              await _bluetooth.requestEnableBluetooth();
              await Future.delayed(const Duration(seconds: 1));
              _checkHardwareStatus();
            },
          ),
        ],
      ),
    );
  }

  Widget _permissionMissingBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x28F59E0B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amberAccent, width: 1.5),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.security, color: Colors.amberAccent, size: 22),
              SizedBox(width: 8),
              Text(
                'Permissions Required',
                style: TextStyle(
                  color: Colors.amberAccent,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Nearby Bluetooth and Location permissions are required to scan & advertise.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () async {
              await _bluetooth.requestPermissions();
              _checkHardwareStatus();
            },
            child: const Text('GRANT PERMISSIONS', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _centralEmergencyButton() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // High-intensity animated pulsing waves during active SOS
          if (_isBroadcastingSos) ...[
            ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.accentCrimson.withOpacity(0.6), width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accentCrimson.withOpacity(0.4),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Main Interactive SOS Button
          GestureDetector(
            onTap: _onBhaiHelpPressed,
            child: Container(
              height: 220,
              width: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _isBroadcastingSos
                    ? const LinearGradient(
                        colors: [Color(0xFFDC2626), Color(0xFF7F1D1D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : AppTheme.sosGradient,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentCrimson.withOpacity(_isBroadcastingSos ? 0.75 : 0.45),
                    blurRadius: 36,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isActivating)
                        const SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3.5,
                          ),
                        )
                      else if (_isBroadcastingSos)
                        const Icon(Icons.podcasts, color: Colors.white, size: 55)
                      else
                        const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 55),
                      const SizedBox(height: 10),
                      Text(
                        _isBroadcastingSos
                            ? '🚨 BROADCASTING\nSOS'
                            : (_isActivating ? 'ACTIVATING...' : '🚨 BHAI HELP'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isBroadcastingSos
                            ? 'TRANSMITTING VIA BLE'
                            : (_isActivating ? 'ACQUIRING GPS' : 'TAP IN AN EMERGENCY'),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final Color borderColor = _isBroadcastingSos
        ? AppTheme.accentCrimson
        : (!_isBluetoothOn ? Colors.redAccent : Colors.white12);
    final IconData icon = _isBroadcastingSos
        ? Icons.podcasts
        : (!_isBluetoothOn ? Icons.bluetooth_disabled : Icons.shield_outlined);
    final Color iconColor = _isBroadcastingSos
        ? AppTheme.accentCrimson
        : (!_isBluetoothOn ? Colors.redAccent : Colors.greenAccent);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: iconColor.withOpacity(0.15),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusMessage,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: iconColor,
                  ),
                ),
                if (_acknowledgedHelperId != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Helper BHAI-$_acknowledgedHelperId has responded to your distress signal!',
                    style: const TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeBroadcastCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0x1CDC2626),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.accentCrimson, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.wifi_tethering, color: AppTheme.accentCrimson),
              SizedBox(width: 10),
              Text(
                'LIVE EMERGENCY BROADCAST',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _detailRow('Emergency ID', _emergencyId ?? 'BHAI-${_bluetooth.myDeviceId}', Colors.cyanAccent),
          const SizedBox(height: 6),
          _detailRow(
            'GPS Coordinates',
            _currentPosition != null
                ? '${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}'
                : 'Not acquired (Indoor / BLE Proximity active)',
            _currentPosition != null ? Colors.greenAccent : Colors.grey,
          ),
          const SizedBox(height: 6),
          _detailRow('BLE Airwaves', 'Transmitting 2.4GHz SOS Beacon', Colors.amberAccent),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF334155),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.white24),
              ),
            ),
            icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
            label: const Text('STOP EMERGENCY BROADCAST', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _confirmStopBroadcast,
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 12, color: valueColor, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _liveLocationActiveCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x1810B981),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.greenAccent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'LIVE LOCATION STREAM ACTIVE (5s)',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _detailRow('Session ID', _liveSessionId?.substring(0, 8) ?? 'Active', Colors.cyanAccent),
          const SizedBox(height: 4),
          _detailRow('Frequency', 'Every 5 Seconds', Colors.greenAccent),
          const SizedBox(height: 4),
          _detailRow(
            'Coordinates',
            _currentPosition != null
                ? '${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}'
                : 'Streaming GPS',
            Colors.white,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Colors.redAccent),
              ),
            ),
            icon: const Icon(Icons.stop_circle, size: 18),
            label: const Text('STOP LIVE STREAM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            onPressed: _toggleLiveLocationStream,
          ),
        ],
      ),
    );
  }

  Widget _liveLocationDisplayCard() {
    final pos = _currentPosition;
    final lat = pos?.latitude;
    final lon = pos?.longitude;
    final hasCoords = lat != null && lon != null && (lat != 0.0 || lon != 0.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.3), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.location_on, color: Colors.cyanAccent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '📍 LIVE LOCATION',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (_isLiveLocationSharing)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('LIVE 5s', style: TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  hasCoords
                      ? '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}'
                      : 'Acquiring GPS fix...',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasCoords
                      ? 'Accuracy ±${pos?.accuracy.toStringAsFixed(0) ?? "8"}m • Updated just now'
                      : 'Waiting for satellite signal',
                  style: TextStyle(
                    color: hasCoords ? Colors.greenAccent : Colors.grey,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Direct Navigation Arrow Button on the right side
          IconButton(
            icon: const Icon(Icons.navigation_rounded, color: Colors.cyanAccent, size: 28),
            tooltip: 'Navigate via Google Maps',
            onPressed: () => _openNavigation(lat, lon),
          ),
        ],
      ),
    );
  }

  Widget _actionButtonsGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _actionTile(
                icon: Icons.radar,
                iconColor: Colors.cyanAccent,
                label: 'Find Nearby\nBhai Users',
                isLoading: _isLoadingNearby,
                onTap: _findNearbyBhai,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionTile(
                icon: _isLiveLocationSharing ? Icons.stream : Icons.share_location,
                iconColor: _isLiveLocationSharing ? Colors.greenAccent : Colors.amberAccent,
                label: _isLiveLocationSharing ? 'Stop Live\nStream' : 'Share Live\nLocation (5s)',
                isActive: _isLiveLocationSharing,
                onTap: _toggleLiveLocationStream,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _actionTile(
                icon: Icons.navigation_outlined,
                iconColor: Colors.lightGreenAccent,
                label: 'Open Google\nMaps Route',
                onTap: () => _openNavigation(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionTile(
                icon: Icons.copy_all_outlined,
                iconColor: Colors.orangeAccent,
                label: 'Copy Live\nLocation Link',
                onTap: () => _shareLocationLink(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _actionTile(
                icon: Icons.bluetooth_audio,
                iconColor: const Color(0xFF38BDF8),
                label: 'Bluetooth Mesh\nOffline Chat',
                onTap: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => const BluetoothMeshChatDialog(),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
    bool isLoading = false,
    bool isActive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isActive ? iconColor.withOpacity(0.12) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? iconColor : Colors.white12,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            if (isLoading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.cyanAccent),
              )
            else
              Icon(icon, color: iconColor, size: 26),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isActive ? iconColor : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
