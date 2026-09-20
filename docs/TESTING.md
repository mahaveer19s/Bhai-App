# Bhai Automated & Field Testing Guide

## 1. Automated Backend Test Suite

Run the full automated test suite covering security, geospatial queries, live location, chat, and concurrency:

```bash
$env:DATABASE_URL="postgresql+asyncpg://bhai:testpass@localhost:5432/bhai"
$env:JWT_SECRET="supersecretlongjwtsecret12345678901234"
$env:OTP_HMAC_SECRET="supersecretlongotphmacsecret123456789012"
pytest backend/tests -v
```

### Coverage
- `test_admin_security.py`: Admin auth and role protection.
- `test_api.py`: Schemas, OTP hashing, and health checks.
- `test_chat_api.py`: Conversation isolation and message lifecycle.
- `test_concurrency.py`: Concurrent multi-user SOS and idempotency.
- `test_live_location.py`: Independent 5s location streaming.
- `test_nearby_users.py`: PostGIS/Haversine geospatial discovery.
- `test_responder_flow.py`: `GOING_TO_HELP` -> `REACHED` lifecycle.

---

## 2. Field Acceptance Procedures

### A. Online Dual-Phone Test (Phones A & B)
1. Both devices connected to Internet, Bluetooth ON, GPS ON.
2. Phone A presses SOS:
   - Phone A displays `🚨 SOS ACTIVE` immediately in $<50\text{ms}$.
   - Siren audio starts.
3. Phone B receives emergency alert dialog with Phone A's location and distance.
4. Phone B taps `[ 💬 CHAT ]`: Phone A and B communicate in real time over WebSockets.
5. Phone B taps `[ 🏃 I'M COMING ]`: Phone A sees helper confirmation.
6. Phone B taps `[ 📍 NAVIGATE ]`: Google Maps launches toward Phone A's GPS coordinates.
7. Phone B reaches Phone A and taps `[ 🏁 REACHED ]`: Phone A and Admin panel see reached confirmation.

### B. Offline Bluetooth Mesh Test (No Internet)
1. Turn OFF Mobile Data and Wi-Fi on both devices; keep Bluetooth ON.
2. Phone A presses SOS.
3. Phone B taps "Find Nearby" -> Discovers Phone A as `📡 Bluetooth Direct`.
4. Phone B opens chat with Phone A -> Sends text message over BLE radio.
5. Phone A receives message via BLE radio chunk reassembly and displays `📡 Bluetooth Direct`.
