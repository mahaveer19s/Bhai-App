import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

class ShakeService {
  static final ShakeService _instance = ShakeService._internal();
  factory ShakeService() => _instance;
  ShakeService._internal();

  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;
  DateTime? _lastShakeTime;

  // Configuration constants
  static const double shakeThreshold = 15.0; // Acceleration magnitude threshold (m/s^2)
  static const int shakeCooldownMs = 1500; // Cooldown to prevent multiple triggers

  /// Starts listening for shake events. Calls [onShake] when a shake is detected.
  void startListening(Function() onShake) {
    if (_accelerometerSubscription != null) return;

    _accelerometerSubscription = userAccelerometerEventStream().listen(
      (UserAccelerometerEvent event) {
        // Calculate the vector magnitude of user acceleration
        final double magnitude = sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        );

        if (magnitude > shakeThreshold) {
          final now = DateTime.now();
          if (_lastShakeTime == null || 
              now.difference(_lastShakeTime!).inMilliseconds > shakeCooldownMs) {
            _lastShakeTime = now;
            onShake();
          }
        }
      },
      onError: (error) {
        debugPrint('Accelerometer service error: $error');
      },
      cancelOnError: true,
    );
  }

  /// Stops listening for shake events.
  void stopListening() {
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
  }
}
