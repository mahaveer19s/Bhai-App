import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PowerSosService {
  static final PowerSosService _instance = PowerSosService._internal();
  factory PowerSosService() => _instance;
  PowerSosService._internal();

  // EventChannel to communicate screen toggle changes from native code
  static const EventChannel _screenChannel = EventChannel('com.bhai.app/screen_events');
  StreamSubscription? _screenSubscription;

  int _toggleCount = 0;
  DateTime? _firstToggleTime;
  
  // Configuration constants
  static const int maxWindowSeconds = 5;
  static const int requiredToggles = 5;

  /// Starts listening to screen toggles. When 5 screen toggles are detected
  /// within [maxWindowSeconds], [onTrigger] is executed.
  void startListening(Function() onTrigger) {
    if (_screenSubscription != null) return;

    /*
      DEVELOPER NOTE: Android/iOS Platform Interception Constraints
      Neither Android nor iOS permits arbitrary background interception of the physical Power key.
      To support the 5-Click SOS trigger, we register a BroadcastReceiver in Android for 
      Intent.ACTION_SCREEN_ON and Intent.ACTION_SCREEN_OFF, and notify this Flutter stream.
      On iOS, we subscribe to Darwin notifications for "com.apple.springboard.lockstate".
    */
    _screenSubscription = _screenChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        _handleScreenToggle(onTrigger);
      },
      onError: (error) {
        debugPrint('Screen event stream error: $error');
      }
    );
  }

  void _handleScreenToggle(Function() onTrigger) {
    final now = DateTime.now();
    
    if (_firstToggleTime == null || now.difference(_firstToggleTime!).inSeconds > maxWindowSeconds) {
      _firstToggleTime = now;
      _toggleCount = 1;
    } else {
      _toggleCount++;
      if (_toggleCount >= requiredToggles) {
        _toggleCount = 0;
        _firstToggleTime = null;
        onTrigger();
      }
    }
  }

  /// Stops monitoring power screen toggles.
  void stopListening() {
    _screenSubscription?.cancel();
    _screenSubscription = null;
  }
}
