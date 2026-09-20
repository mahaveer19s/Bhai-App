# Testing Strategy, Concurrency Benchmarks & Physical Device Matrix — BHAI

This document outlines the complete automated test suite, concurrency load benchmarks, and the physical Android device testing matrix for the **BHAI Emergency Assistance Platform**.

---

## 🧪 Testing Verification Levels

Every requirement and test in this repository is categorized into one of the following verification tiers:

| Tier | Definition |
| :--- | :--- |
| **`AUTOMATED TESTED`** | Verified via deterministic unit, integration, or async concurrency pytest suites. |
| **`REAL DEVICE TESTED`** | Verified on physical Android hardware running the compiled APK. |
| **`REQUIRES REAL DEVICE TEST`** | Requires multi-phone physical hardware testing for final field sign-off. |
| **`REQUIRES DEPLOYMENT TEST`** | Requires production TLS/WSS reverse proxy infrastructure. |

---

## ⚡ Automated Pytest Suite (30 Test Cases)

The backend automated test suite verifies API integrity, multi-victim concurrency isolation, authentication, RBAC, live streaming, and geospatial calculations.

### Running Backend Tests
```powershell
$env:TESTING="1"
$env:DATABASE_URL="sqlite+aiosqlite:///:memory:"
$env:JWT_SECRET="test_secret_for_pytest_environment_2026"
$env:OTP_HMAC_SECRET="test_otp_secret_for_pytest_2026"
pytest backend/tests -v
```

### Test Suite Coverage Breakdown

```text
backend/tests/
├── test_admin_security.py
│   ├── test_admin_endpoints_reject_unauthenticated         [PASSED]
│   ├── test_admin_endpoints_reject_normal_user             [PASSED]
│   └── test_admin_login_lifecycle_and_access               [PASSED]
├── test_api.py
│   ├── test_security_otp_generation                        [PASSED]
│   ├── test_security_otp_verification                      [PASSED]
│   ├── test_security_jwt_token_lifecycle                   [PASSED]
│   ├── test_security_jwt_invalid_token                     [PASSED]
│   ├── test_auth_request_schema                            [PASSED]
│   ├── test_verify_otp_request_schema                      [PASSED]
│   ├── test_emergency_create_schema_validation             [PASSED]
│   ├── test_emergency_cancel_schema                        [PASSED]
│   ├── test_relay_message_create_schema                    [PASSED]
│   ├── test_police_dispatcher_safe_test_mode               [PASSED]
│   ├── test_health_endpoint                                [PASSED]
│   └── test_openapi_spec                                   [PASSED]
├── test_chat_api.py
│   ├── test_chat_conversation_and_message_lifecycle        [PASSED]
│   └── test_unauthorized_user_cannot_access_private_chat   [PASSED]
├── test_concurrency.py
│   ├── test_concurrent_emergency_alerts_multiple_users     [PASSED]
│   ├── test_concurrent_live_location_streams_independent   [PASSED]
│   └── test_user_idempotency_prevents_duplicate_emergencies[PASSED]
├── test_live_location.py
│   ├── test_live_location_lifecycle                        [PASSED]
│   └── test_live_location_ownership_isolation              [PASSED]
├── test_multi_victim_concurrency.py
│   ├── test_two_victims_simultaneous_sos                   [PASSED]
│   ├── test_ten_victims_simultaneous_sos_isolation         [PASSED]
│   ├── test_hundred_victims_concurrent_sos                 [PASSED]
│   ├── test_thousand_simulated_victims_scale_concurrency   [PASSED]
│   ├── test_dual_transport_idempotency_deduplication       [PASSED]
│   └── test_haversine_geodesic_distance_calculation        [PASSED]
├── test_nearby_users.py
│   └── test_nearby_users_geospatial_discovery              [PASSED]
└── test_responder_flow.py
    └── test_responder_lifecycle_coming_to_reached          [PASSED]

============================== 30 passed in 9.10s ==============================
```

---

## 📱 Flutter Client Test Suite

```powershell
cd bhai_app
flutter test
```

Verifies:
- Haversine mathematical proximity algorithm.
- Emergency protocol packet serialization & HMAC signing.
- Emergency state machine transitions (`idle` → `triggered` → `active` → `cancelled`).
- BLE RSSI distance approximation ranking.
- Home screen widget rendering.

---

## 📱 Physical Android Device Test Matrix

To formally certify Bluetooth mesh discovery and hardware GPS accuracy, execute this matrix with **at least 3 physical Android phones**:

```text
[ PHONE A ] = Victim 1 (Android 13)
[ PHONE B ] = Helper 1 (Android 14)
[ PHONE C ] = Helper 2 (Android 12)
[ PHONE D ] = Victim 2 (Android 11)
```

### Scenario 1: Multi-Victim Simultaneous SOS
1. **Victim 1 (Phone A)** and **Victim 2 (Phone D)** trigger SOS at the exact same instant.
2. **Verify on Helper 1 (Phone B):**
   - Helper sees two distinct emergency cards: `EMERGENCY A` and `EMERGENCY B`.
   - Each card displays real GPS distance computed from Helper's own GPS fix.
   - Helper clicks `I'M COMING` on Emergency A.
3. **Verify on Victim 1 (Phone A):**
   - Screen updates: `👥 1 member is coming to help`.
4. **Verify on Victim 2 (Phone D):**
   - Screen remains: `⚠️ 0 members responding` (completely isolated).
5. **Victim 1 resolves SOS:**
   - Emergency A disappears from Helper's list. Emergency B remains active.

---

### Scenario 2: Internet-Only Mode (Bluetooth OFF)
1. Turn **Bluetooth OFF** completely on all test phones. Keep Wi-Fi/Mobile Data **ON**.
2. Victim presses SOS.
3. **Verify:**
   - Real GPS coordinates transmitted to backend.
   - Nearby helpers receive immediate push notification and emergency dialog.
   - Navigation button `[ ➤ ]` opens Google Maps directly with real destination coordinates.
   - Chat operates smoothly over WebSocket/REST without requiring Bluetooth.

---

### Scenario 3: Bluetooth-Only Offline Mode (Internet OFF)
1. Turn **Wi-Fi and Mobile Data OFF** completely on all test phones. Keep **Bluetooth ON**.
2. Victim presses SOS.
3. **Verify:**
   - Audio siren triggers locally on victim's device.
   - Foreground BLE advertiser broadcasts 2.4 GHz distress packet.
   - Nearby helper running Bhai App discovers the BLE beacon within ~1-5 seconds.
   - Dialog displays `📡 Bluetooth Direct` transport indicator.
   - Coordinates from last valid satellite fix are rendered.

---

### Scenario 4: Dual-Transport Deduplication (Internet + BLE ON)
1. Turn **Internet ON** and **Bluetooth ON** on all devices.
2. Victim presses SOS.
3. Helper receives alert via both BLE airwaves and Internet WebSocket.
4. **Verify:**
   - Helper UI displays **exactly ONE** merged emergency card with `🌐 Internet + 📡 Bluetooth` badge.
   - Idempotency key prevents duplicate cards, duplicate push alerts, and duplicate chat bubbles.
