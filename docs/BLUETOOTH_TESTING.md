# BHAI Real Device Bluetooth Testing & Validation Matrix

## 1. Testing Prerequisites
- **Hardware Tested**:
  - Device A: Physical Android Phone (API 34, Android 14)
  - Device B: Physical Android Phone (API 33, Android 13)
  - Device C: Laptop with Windows 11 Bluetooth 5.2
- **Required OS Permissions**:
  - Android 12+ (API 31+): `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION`
  - Android 6.0 - 11: `ACCESS_FINE_LOCATION`

---

## 2. Validation Test Scenarios

### Test 1: Real Device Discovery (Phone A $\leftrightarrow$ Phone B)
- **Action**: Launch Bhai App on Phone A and Phone B. Both keep Bluetooth ON.
- **Verification**:
  - Phone B opens "Find Nearby Bhai".
  - Phone B discovers Phone A's 4-byte Ephemeral ID.
  - RSSI is measured and displayed with qualitative proximity tag (`Within ~5-15m (Very Near)`).
  - Unrelated laptops/Bluetooth earbuds are ignored by hardware scan filters.

### Test 2: Offline Emergency Alert & Navigation Trigger
- **Action**: Disable Wi-Fi and Mobile Data on Phone A and Phone B. Phone A activates SOS.
- **Verification**:
  - Phone A broadcasts Type `0x02` BLE packet with packed latitude and longitude.
  - Phone B immediately displays the full-screen pulsing `EmergencyReceivedDialog`.
  - Phone B taps **"I'M GOING TO HELP"** $\rightarrow$ BLE ACK is broadcast $\rightarrow$ Google Maps launches navigation to Phone A's coordinates.

### Test 3: Offline Direct Chat over BLE Radio
- **Action**: Keep Internet OFF on both devices.
- **Verification**:
  - Open Emergency Chat.
  - Send: *"Where are you?"* $\rightarrow$ Transport tag displays `📡 Bluetooth Direct Radio`.
  - Message is broadcast and received by Phone A.

### Test 4: Laptop Bluetooth Baseline Verification
- **Action**: Laptop running Windows with standard Bluetooth turned on.
- **Verification**:
  - Standard laptop does not participate in the `BHAI` protocol and is NOT displayed as a Bhai helper.
