# BHAI SOS Siren & Audio Policy Documentation

## 1. Native Siren Engine
- **Audio Generation**: Uses Android `ToneGenerator` connected to `AudioManager.STREAM_ALARM` with volume 100%.
- **Pattern**: Dual-tone emergency siren alternating between `TONE_CDMA_EMERGENCY_RINGBACK` and `TONE_CDMA_ALERT_CALL_GUARD` every 500 milliseconds.
- **Loop Control**: Handled via `Handler` and `Looper.getMainLooper()` with instant release on `stopEmergencySiren`.

---

## 2. Android System Limitations & Honest Audio Disclosure
- **Do Not Disturb (DND) & Silent Mode**: Android OS security prevents non-system apps from secretly forcing a device out of DND mode unless the user has explicitly granted **Notification Policy Access (DND Bypass)** in Android Settings.
- **High Importance Notification Channel**: BHAI creates notification channels with `Importance.max` and `Priority.high` to request maximum sound priority where permitted by the operating system.
- **Immediate Termination**: Siren stops instantaneously when the user taps "STOP SOS" or resolves the emergency.
