import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';

class CancellationCountdownDialog extends StatefulWidget {
  const CancellationCountdownDialog({super.key, this.durationSeconds = 15});

  final int durationSeconds;

  @override
  State<CancellationCountdownDialog> createState() => _CancellationCountdownDialogState();
}

class _CancellationCountdownDialogState extends State<CancellationCountdownDialog> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.durationSeconds;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remaining <= 1) {
        timer.cancel();
        if (mounted) Navigator.pop(context, false); // Countdown expired -> continue emergency
      } else {
        try {
          HapticFeedback.lightImpact();
        } catch (_) {}
        if (mounted) {
          setState(() {
            _remaining--;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent accidental dismissal via back button
      child: AlertDialog(
        backgroundColor: const Color(0xFF1E1B4B), // Deep indigo
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.accentCrimson, size: 64),
            const SizedBox(height: 16),
            const Text(
              'EMERGENCY ALERT ACTIVE',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Your emergency alert is being transmitted to your safety network.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 90,
                  height: 90,
                  child: CircularProgressIndicator(
                    value: _remaining / widget.durationSeconds,
                    strokeWidth: 8,
                    color: AppTheme.accentCrimson,
                    backgroundColor: Colors.white24,
                  ),
                ),
                Text(
                  '$_remaining',
                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white60, width: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
                onPressed: () {
                  _timer?.cancel();
                  Navigator.pop(context, true); // Cancel button pressed -> cancel emergency
                },
                child: const Text('CANCEL EMERGENCY', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
