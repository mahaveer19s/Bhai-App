# BHAI — Platform Capabilities & Technical Limitations (Android vs. iOS)

This document provides a technical, legal, and operational analysis of operating system capabilities and platform limitations for **BHAI** (Offline-First Women's Safety Network).

---

## 1. Bluetooth Low Energy (BLE) Local Discovery & Advertising

### Android (`android/app/src/main/kotlin/com/bhai/bhai_app/MainActivity.kt`)
* **Advertising**: Supported via `BluetoothLeAdvertiser` (Android 5.0+ / API 21+). Requires `BLUETOOTH_ADVERTISE` runtime permission on Android 12+ (API 31+).
* **Scanning**: Supported via `BluetoothLeScanner`. Uses `ScanFilter` with service UUID `7c3e4eae-a1ae-4f7d-b6f2-9a110a11a001`.
* **Background Restrictions**:
  * On Android 8.0+ (API 26+), background scanning requires low-power settings or a **Foreground Service** with an active notification.
  * Vendor-specific battery optimization (e.g., Xiaomi MIUI, Samsung One UI, Huawei EMUI) may kill background BLE processes unless battery optimization exemption is granted by the user.
* **Store-and-Forward Mesh**: Supported via local SQLite encryption (`sqflite`). Devices receiving a BLE packet store it locally and attempt backend sync when internet connectivity is detected.

### iOS (`ios/Runner/AppDelegate.swift`)
* **Advertising**: Supported via `CBPeripheralManager`. Requires `NSBluetoothAlwaysUsageDescription` in `Info.plist`.
* **Scanning**: Supported via `CBCentralManager` with specified service UUIDs.
* **Background Restrictions**:
  * When the app is in the background, Apple OS rules shift the device local name out of the advertisement packet and place service UUIDs in a dedicated overflow area.
  * Scanning in the background operates at reduced duty cycles; duplicate filtering is strictly enforced by iOS.
  * iOS does **NOT** allow arbitrary mesh relaying when the app is fully terminated by the user (force quit).
* **Store-and-Forward Mesh**: Supported while the app is active, in background location mode, or background BLE mode.

---

## 2. Location Tracking & Background Access

### Android
* **Foreground Service**: Using a foreground service with type `location` allows continuous GPS tracking during an active emergency, showing a persistent notification icon.
* **Background Location**: Requires `ACCESS_BACKGROUND_LOCATION` permission (Android 10+). Must be requested separately from fine location with explicit user explanation.
* **Last Known Location**: If GPS fixes are temporarily unavailable (e.g., indoors or underground), the system uses the last cached location and marks `locationSource = LAST_KNOWN`.

### iOS
* **Authorization Levels**:
  * `When In Use`: Allows GPS updates while the app is active or in background with a visible blue status bar indicator (`allowsBackgroundLocationUpdates = true`).
  * `Always`: Allows background location updates without the status bar indicator.
* **App Termination**: Significant Location Change API can re-wake the app on movement even after app restart.

---

## 3. Physical Device Shutdown / Power Off

> [!IMPORTANT]
> **Technical Reality**: Neither Android nor iOS allows mobile applications to continue executing code after a device is physically powered off or loses battery completely.

### Store-and-Forward Protection
- When Phone A triggers an emergency:
  1. The emergency packet is immediately written to local encrypted database.
  2. The packet is broadcast via BLE to nearby Phone B.
  3. If Phone A is subsequently powered off, Phone B retains the encrypted packet.
  4. Once Phone B gains internet access, it uploads the packet to the BHAI backend server on behalf of Phone A.
  5. Emergency contacts and control rooms are notified successfully.

---

## 4. Emergency Calling & Telephony Integration

### Android
* Triggers native phone dialer via `Intent.ACTION_DIAL` with `tel:112` (or locally configured emergency number).
* Direct call dialing (`Intent.ACTION_CALL`) is restricted on Google Play Store without explicit telephony permission exceptions; therefore, `ACTION_DIAL` is used to allow immediate user call trigger.

### iOS
* Triggers native `tel:` URL scheme (`UIApplication.shared.open(url)`).
* Requires user confirmation in the iOS system alert before initiating the call.

---

## 5. Compliance & Policy Guidelines

1. **Google Play Store Policy**:
   * Background location permissions must undergo Google Play Console declaration review.
   * Prominent in-app disclosure must precede permission requests.
2. **Apple App Store Review Guidelines (Guideline 2.5.4 - Multitasking)**:
   * Background BLE and Location modes must be genuinely tied to safety features.
   * Disclaimer required: *"Continued use of GPS running in the background can dramatically decrease battery life."*
3. **Legal Disclaimer**:
   * BHAI is a community assistance tool and communications network. It does not replace official emergency services (112 / 911) or guarantee emergency dispatch.
