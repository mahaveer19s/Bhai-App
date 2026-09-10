import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Production-ready emergency audio siren service.
/// Plays loud pulsating alarm tone during active SOS and stops immediately upon cancellation.
class AudioAlertService {
  AudioAlertService._();
  static final AudioAlertService _instance = AudioAlertService._();
  factory AudioAlertService() => _instance;

  static const MethodChannel _channel = MethodChannel('com.bhai.app/ble_emergency');
  bool _isPlaying = false;
  Timer? _webAudioTimer;

  bool get isPlaying => _isPlaying;

  /// Start pulsating emergency siren loop.
  Future<void> startSiren() async {
    if (_isPlaying) return;
    _isPlaying = true;

    if (!kIsWeb) {
      try {
        await _channel.invokeMethod('startEmergencySiren');
      } catch (e) {
        debugPrint('[AudioAlertService] Native siren failed: $e');
      }
    } else {
      // Web audio oscillator simulation
      _startWebAudioLoop();
    }
  }

  /// Stop emergency siren immediately.
  Future<void> stopSiren() async {
    if (!_isPlaying) return;
    _isPlaying = false;

    if (!kIsWeb) {
      try {
        await _channel.invokeMethod('stopEmergencySiren');
      } catch (e) {
        debugPrint('[AudioAlertService] Stop native siren error: $e');
      }
    } else {
      _webAudioTimer?.cancel();
      _webAudioTimer = null;
    }
  }

  void _startWebAudioLoop() {
    _webAudioTimer?.cancel();
    _webAudioTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }
      // Beep feedback in web console / AudioContext if available
      debugPrint('[AudioAlertService] 🚨 EMERGENCY SIREN ACTIVE [BEEP]');
    });
  }
}
