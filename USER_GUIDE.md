# BHAI App — Complete User & Deployment Guide

Welcome to **BHAI App**, the decentralized community safety and emergency dispatch network with dual-rail Internet & Bluetooth Low Energy mesh communication.

---

## 📱 How to Use Bhai App

### 1. First-Run Setup & Permissions
1. Download and install the APK on your Android device:
   - **Download URL**: `http://10.140.120.82:8080/Bhai_App_Latest.apk` (or via FastAPI backend at `/download-apk`)
2. On first launch, tap **"ALLOW ALL PERMISSIONS"**:
   - **Notifications**: Required to receive loud emergency alarms and chat messages even when Bhai is closed or the screen is off.
   - **Bluetooth & Location**: Required for 2.4GHz offline mesh discovery and GPS coordinate sharing.
   - **Battery Optimization Exemption**: Whitelists Bhai from Android battery managers so the background safety guard runs 24/7.

---

### 2. Victim Mode: Triggering an Emergency
1. Tap the large pulsing red **"🚨 BHAI HELP"** button on the home screen.
2. The app immediately:
   - Starts a loud local emergency siren.
   - Broadcasts high-priority 2.4GHz Bluetooth Low Energy emergency beacons.
   - Streams live satellite GPS coordinates every 5 seconds to the central network.
   - Alerts all nearby Bhai users and community responders.
3. Once a nearby helper taps **"I'M COMING"**, you will see:
   - Helper confirmation banner: `Helper BHAI-XXXX confirmed: I AM COMING! 🏃`
   - Real-time chat dialogue to communicate directly with the helper.
4. When safe, tap **"STOP SOS"**:
   - Siren silences instantly (<5ms).
   - Live location sharing and BLE broadcasting stop immediately.
   - The app resets cleanly to **Standby**, ready for any future emergency.

---

### 3. Helper / Volunteer Mode: Responding to an Alert
1. When a nearby person triggers SOS:
   - Your phone immediately sounds an **audible emergency alarm** and vibrates, displaying a full-screen alert.
   - Tap the notification to jump straight into the emergency screen.
2. View the emergency details:
   - Distance (computed via real geodesic Haversine distance).
   - Victim's live satellite GPS coordinates.
3. Tap **"I'M COMING"**:
   - Sends an immediate acknowledgment back to the victim.
   - Automatically opens **Google Maps turn-by-turn navigation** directly to the victim's location.
4. Tap **"💬 OPEN CHAT"** to coordinate directly with the victim over Internet or offline Bluetooth mesh.

---

### 4. Dual-Rail Realtime & Offline Chat
- **With Internet**: Messages sync near-instantly over WebSockets / REST API.
- **Without Internet (Offline)**: Messages transmit directly between devices over 2.4GHz Bluetooth Low Energy mesh packets (Type 0x04) without cellular data or Wi-Fi.
- **With Both Internet & Bluetooth**: Recipient automatically deduplicates incoming packets, displaying exactly **one** message bubble.

---

### 5. Multi-Victim Emergency Isolation
- Each emergency is uniquely identified by `emergency_id` and `client_event_id`.
- If multiple victims trigger SOS at the same time:
  - Responders view separate cards for each emergency.
  - Chat rooms, coordinates, and navigation routes remain strictly isolated.
  - Resolving one emergency has zero effect on other active emergencies.

---

## 🖥️ Web Admin Command Center
1. Open your browser to: `http://localhost:3001` (or backend at `http://localhost:8000/admin`)
2. View real-time active incidents, responder counts, live GPS markers, and audit logs.
3. Operators can trigger test alerts, review cryptographic device IDs, and monitor network health.

---

## 🛠️ Testing Verification Commands
```powershell
# Run backend test suite (30 test cases)
$env:TESTING="1"; $env:DATABASE_URL="sqlite+aiosqlite:///:memory:"; $env:JWT_SECRET="test_secret_for_pytest_environment_2026"; $env:OTP_HMAC_SECRET="test_otp_secret_for_pytest_2026"; backend\.venv\Scripts\python.exe -m pytest backend/tests -v

# Run Flutter mobile test suite (8 test cases)
temp_flutter_sdk\flutter\bin\flutter.bat test

# Build latest Android APK
temp_flutter_sdk\flutter\bin\flutter.bat build apk --debug
```
