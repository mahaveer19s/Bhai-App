import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/services/bluetooth_service.dart';
import '../../../../core/theme/app_theme.dart';

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
  double? _calculatedDistanceMeters;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _calculateRealDistance();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _calculateRealDistance() async {
    if (widget.alert.hasLocation && widget.alert.latitude != null && widget.alert.longitude != null) {
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) {
          final distance = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            widget.alert.latitude!,
            widget.alert.longitude!,
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
    if (widget.alert.hasLocation &&
        widget.alert.latitude != null &&
        widget.alert.longitude != null &&
        (widget.alert.latitude != 0.0 || widget.alert.longitude != 0.0)) {
      await BluetoothService().openGoogleMaps(widget.alert.latitude!, widget.alert.longitude!);
    }
  }


  void _onNavigateToPerson() async {
    if (widget.alert.hasLocation && widget.alert.latitude != null && widget.alert.longitude != null) {
      await BluetoothService().openGoogleMaps(widget.alert.latitude!, widget.alert.longitude!);
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
    final hasCoords = widget.alert.hasLocation &&
        widget.alert.latitude != null &&
        widget.alert.longitude != null &&
        (widget.alert.latitude != 0.0 || widget.alert.longitude != 0.0);

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
              const SizedBox(height: 18),

              // Details Information Card - REAL DATA ONLY
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    _infoRow(
                      Icons.tag,
                      'Emergency ID',
                      widget.alert.emergencyId,
                      Colors.cyanAccent,
                    ),
                    const Divider(height: 16, color: Colors.white10),
                    _infoRow(
                      Icons.location_on,
                      'Location',
                      hasCoords
                          ? '${widget.alert.latitude!.toStringAsFixed(5)}, ${widget.alert.longitude!.toStringAsFixed(5)}'
                          : 'Not provided by sender (Proximity via BLE)',
                      hasCoords ? Colors.greenAccent : Colors.grey,
                    ),
                    const Divider(height: 16, color: Colors.white10),
                    _infoRow(
                      Icons.access_time,
                      'Time',
                      _formatTime(widget.alert.triggeredAt),
                      Colors.white70,
                    ),
                    const Divider(height: 16, color: Colors.white10),
                    _infoRow(
                      Icons.near_me,
                      'Distance',
                      _calculatedDistanceMeters != null
                          ? '~${_calculatedDistanceMeters!.toStringAsFixed(0)} meters away\n(${widget.alert.estimatedDistance})'
                          : widget.alert.estimatedDistance,
                      Colors.amberAccent,
                    ),
                    const Divider(height: 16, color: Colors.white10),
                    _infoRow(
                      Icons.wifi_tethering,
                      'Transport',
                      '${widget.alert.source} (Direct Airwaves)',
                      Colors.blueAccent,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              if (_hasResponded) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0x2234D399),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Response Confirmed!\nBLE ACK sent: I'M GOING TO HELP.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // If coordinates exist, show Navigate button even after responding
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
                      icon: const Icon(Icons.navigation, size: 22),
                      label: const Text('📍 NAVIGATE (GOOGLE MAPS)', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _onNavigateToPerson,
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
                    child: const Text('DISMISS'),
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
