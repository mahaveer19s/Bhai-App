import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/emergency_service.dart';
import '../../../core/theme/app_theme.dart';

class EmergencyStatusScreen extends StatefulWidget {
  const EmergencyStatusScreen({super.key});

  @override
  State<EmergencyStatusScreen> createState() => _EmergencyStatusScreenState();
}

class _EmergencyStatusScreenState extends State<EmergencyStatusScreen> {
  final EmergencyService _emergency = EmergencyService();
  Timer? _refreshTimer;
  int _helpers = 0;
  bool _isSyncing = true;

  @override
  void initState() {
    super.initState();
    _resumeAndRefresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 12), (_) => _refresh());
  }

  Future<void> _resumeAndRefresh() async {
    await _emergency.resumeActiveEmergency();
    await _refresh();
  }

  Future<void> _refresh() async {
    try {
      await _emergency.syncPending();
      final id = _emergency.activeEmergencyId;
      if (id != null) _helpers = await _emergency.responderCount(id);
    } catch (_) {
      // The encrypted queue remains the source of truth until the device reconnects.
    }
    if (mounted) setState(() => _isSyncing = false);
  }

  Future<void> _endEmergency() async {
    final shouldEnd = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Are you sure you are safe?'),
            content: const Text('Ending BHAI stops live location sharing and the offline Bluetooth beacon.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('KEEP ACTIVE')),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('YES, END EMERGENCY'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldEnd) return;
    await _emergency.endEmergency();
    if (mounted) context.go('/home');
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isQueued = _emergency.activeEmergencyId == null;
    return Scaffold(
      backgroundColor: const Color(0xFF2A0810),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 72),
              const SizedBox(height: 16),
              const Text(
                'BHAI EMERGENCY ACTIVE',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: .4),
              ),
              const SizedBox(height: 8),
              Text(
                isQueued
                    ? 'No internet connection. Your alert and location are encrypted on this device and will sync automatically.'
                    : 'Your emergency is saved. Authorized helpers and selected trusted contacts are being notified.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
              const SizedBox(height: 28),
              _statusCard(Icons.location_on, 'GPS location sharing', 'Active while permissions allow'),
              const SizedBox(height: 12),
              _statusCard(
                isQueued ? Icons.cloud_off : Icons.cloud_done,
                'Safety server',
                isQueued ? 'Encrypted sync queue active' : 'Emergency securely stored',
              ),
              const SizedBox(height: 12),
              _statusCard(Icons.people_alt_outlined, 'Nearby helpers', _isSyncing ? 'Checking…' : '$_helpers acknowledged'),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  SystemSound.play(SystemSoundType.alert);
                  HapticFeedback.heavyImpact();
                },
                icon: const Icon(Icons.volume_up),
                label: const Text('MAKE ALERT SOUND'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _callEmergencyNumber,
                icon: const Icon(Icons.phone_in_talk),
                label: const Text('CALL LOCAL EMERGENCY SERVICES'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52)),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _endEmergency,
                icon: const Icon(Icons.shield_outlined),
                label: const Text('I AM SAFE – END EMERGENCY'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  minimumSize: const Size.fromHeight(56),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'BHAI is a community emergency-assistance tool. It does not guarantee rescue, police dispatch, or emergency response.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCard(IconData icon, String title, String subtitle) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white.withOpacity(.1), borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.accentCyan),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );

  Future<void> _callEmergencyNumber() async {
    try {
      await _emergency.openOfficialEmergencyDialer();
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Call your locally configured emergency number (default: 112).')),
      );
    }
  }
}
