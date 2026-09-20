import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/services/api_client.dart';
import '../../../../core/services/bluetooth_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../chat/presentation/bluetooth_mesh_chat_dialog.dart';

/// Prominent, unmissable V2 emergency screen displayed when a nearby Bhai user broadcasts SOS.
/// Features real GPS coordinates, one-tap Google Maps navigation, BLE ACK, and distance telemetry.
class EmergencyReceivedDialog extends StatefulWidget {
  final BhaiEmergencyAlert alert;

  const EmergencyReceivedDialog({
    super.key,
    required this.alert,
  });

  @override
  State<EmergencyReceivedDialog> createState() => _EmergencyReceivedDialogState();
}

class _EmergencyReceivedDialogState extends State<EmergencyReceivedDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  bool _hasResponded = false;
  bool _hasReached = false;
  double? _calculatedDistanceMeters;
  double? _liveLat;
  double? _liveLon;
  DateTime? _lastLocationUpdate;
  Timer? _liveSyncTimer;

  @override
  void initState() {
    super.initState();
    _liveLat = widget.alert.latitude;
    _liveLon = widget.alert.longitude;
    _lastLocationUpdate = widget.alert.triggeredAt;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _calculateRealDistance();
    _startLiveLocationTracking();
  }

  void _startLiveLocationTracking() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final res = await ApiClient().get('/emergencies/active');
        if (res is List && res.isNotEmpty) {
          for (final item in res) {
            final id = item['id']?.toString();
            final sender = item['sender_id']?.toString()?.toUpperCase();
            if (id == widget.alert.emergencyId || sender == widget.alert.senderId.toUpperCase()) {
              final lat = (item['latitude'] as num?)?.toDouble();
              final lon = (item['longitude'] as num?)?.toDouble();
              if (lat != null && lon != null && (lat != 0.0 || lon != 0.0)) {
                if (mounted && (lat != _liveLat || lon != _liveLon)) {
                  setState(() {
                    _liveLat = lat;
                    _liveLon = lon;
                    _lastLocationUpdate = DateTime.now();
                  });
                  _calculateRealDistance();
                }
              }
              break;
            }
          }
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _liveSyncTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _calculateRealDistance() async {
    final targetLat = _liveLat ?? widget.alert.latitude;
    final targetLon = _liveLon ?? widget.alert.longitude;
    if (targetLat != null && targetLon != null && (targetLat != 0.0 || targetLon != 0.0)) {
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) {
          final distance = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            targetLat,
            targetLon,
          );
          if (mounted) {
            setState(() {
              _calculatedDistanceMeters = distance;
            });
          }
        }
      } catch (_) {}
    }
  }

  void _onGoingToHelp() async {
    setState(() => _hasResponded = true);
    await BluetoothService().goingToHelp(widget.alert.senderId, widget.alert.emergencyId);
    final targetLat = _liveLat ?? widget.alert.latitude;
    final targetLon = _liveLon ?? widget.alert.longitude;
    if (targetLat != null && targetLon != null && (targetLat != 0.0 || targetLon != 0.0)) {
      await BluetoothService().openGoogleMaps(targetLat, targetLon);
    }
  }

  void _onReached() async {
    setState(() => _hasReached = true);
    try {
      final pos = await Geolocator.getLastKnownPosition();
      await ApiClient().post(
        '/emergencies/${widget.alert.emergencyId}/respond',
        {
          'response_type': 'REACHED',
          if (pos != null) 'latitude': pos.latitude,
          if (pos != null) 'longitude': pos.longitude,
        },
      );
    } catch (_) {}
    await BluetoothService().broadcastChatMessage(text: 'REACHED', targetId: widget.alert.senderId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Status updated: You have reached the victim.'),
          backgroundColor: Color(0xFF059669),
        ),
      );
    }
  }

  void _onNavigateToPerson() async {
    final targetLat = _liveLat ?? widget.alert.latitude;
    final targetLon = _liveLon ?? widget.alert.longitude;
    if (targetLat != null && targetLon != null && (targetLat != 0.0 || targetLon != 0.0)) {
      await BluetoothService().openGoogleMaps(targetLat, targetLon);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS coordinates not available from sender. Navigating by BLE proximity.'),
        ),
      );
    }
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final effectiveLat = _liveLat ?? widget.alert.latitude;
    final effectiveLon = _liveLon ?? widget.alert.longitude;
    final hasCoords = effectiveLat != null &&
        effectiveLon != null &&
        (effectiveLat != 0.0 || effectiveLon != 0.0);

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppTheme.accentCrimson, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentCrimson.withOpacity(0.55),
                blurRadius: 36,
                spreadRadius: 4,
              ),
            ],
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsing Emergency Beacon
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 85,
                  height: 85,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppTheme.sosGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accentCrimson.withOpacity(0.7),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              const Text(
                '🚨 EMERGENCY NEAR YOU',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),

              // Subtitle
              const Text(
                'A nearby Bhai user has triggered an emergency distress alert.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFFCA5A5),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              // Prominent Location Card with Direct Arrow Button
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00BCD4).withOpacity(0.5), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00BCD4).withOpacity(0.15),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BCD4).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.location_on, color: Color(0xFF00BCD4), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'VICTIM LIVE LOCATION',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('LIVE 5s', style: TextStyle(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            hasCoords
                                ? '${effectiveLat!.toStringAsFixed(5)}, ${effectiveLon!.toStringAsFixed(5)}'
                                : 'Acquiring satellite fix...',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _calculatedDistanceMeters != null
                                ? '~${_calculatedDistanceMeters!.toStringAsFixed(0)}m away • Click arrow to navigate'
                                : '${widget.alert.estimatedDistance} • Click arrow to navigate',
                            style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Direct Navigation Arrow Button on the right side
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2563EB).withOpacity(0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.navigation_rounded, color: Colors.white, size: 26),
                        tooltip: 'Navigate directly with Google Maps',
                        onPressed: _onNavigateToPerson,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (_hasResponded) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _hasReached
                              ? "✅ YOU HAVE REACHED THE SCENE!\nCommunication channel remains active."
                              : "Response Confirmed: I'M COMING!\nVictim & Admin notified.",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Navigate button
                if (hasCoords) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.navigation, size: 20),
                      label: const Text('📍 NAVIGATE (GOOGLE MAPS)', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _onNavigateToPerson,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Emergency Chat button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00BCD4),
                      foregroundColor: const Color(0xFF070B14),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                    label: const Text('💬 OPEN EMERGENCY CHAT', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => BluetoothMeshChatDialog(
                          alertId: widget.alert.emergencyId,
                          helperId: widget.alert.senderId,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),

                // REACHED Button
                if (!_hasReached) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.flag_rounded, size: 20),
                      label: const Text('🏁 I HAVE REACHED (REACHED)', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _onReached,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('CLOSE DIALOG'),
                  ),
                ),
              ] else ...[
                // Action 1: NAVIGATE TO PERSON (Google Maps)
                if (hasCoords) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 6,
                      ),
                      icon: const Icon(Icons.navigation, size: 22),
                      label: const Text(
                        '📍 NAVIGATE TO PERSON',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      onPressed: _onNavigateToPerson,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Action 2: VIEW LOCATION Modal
                if (hasCoords) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.cyanAccent,
                        side: const BorderSide(color: Colors.cyanAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('📍 VIEW LOCATION', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (c) => AlertDialog(
                            backgroundColor: const Color(0xFF0F172A),
                            title: const Text('Emergency GPS Location', style: TextStyle(color: Colors.white)),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Latitude: ${widget.alert.latitude}\nLongitude: ${widget.alert.longitude}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, height: 1.6),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Triggered At: ${_formatTime(widget.alert.triggeredAt)}\nSignal: ${widget.alert.rssi} dBm\nTransport: ${widget.alert.source}',
                                  style: const TextStyle(color: Colors.white70, height: 1.5),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton.icon(
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('COPY'),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(
                                    text: '${widget.alert.latitude},${widget.alert.longitude}',
                                  ));
                                  Navigator.of(c).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Coordinates copied to clipboard')),
                                  );
                                },
                              ),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.navigation, size: 16),
                                label: const Text('NAVIGATE'),
                                onPressed: () {
                                  Navigator.of(c).pop();
                                  _onNavigateToPerson();
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Action 3: I'M GOING TO HELP
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 8,
                    ),
                    icon: const Icon(Icons.directions_run, size: 26),
                    label: const Text(
                      "✅ I'M GOING TO HELP",
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                    onPressed: _onGoingToHelp,
                  ),
                ),
                const SizedBox(height: 10),

                // Action 4: DISMISS
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      '❌ DISMISS',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color iconColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 13),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
