# BHAI Testing & Verification Guide

This guide describes how to perform automated and manual multi-device testing for the BHAI Emergency Assistance Platform.

---

## 1. Automated Test Suite

The backend includes a comprehensive async test suite covering authentication, emergency lifecycle, 5-second live location sessions, nearby user discovery, admin security, and multi-user concurrency.

### Running Backend Tests
```powershell
cd backend
& .\.venv\Scripts\python.exe -m pytest -v
```

### Key Automated Test Coverage:
- `tests/test_api.py`: User registration, OTP authentication, emergency creation, duplicate click prevention (idempotency), trusted contacts.
- `tests/test_live_location.py`: Independent live location sessions, 5-second coordinate streaming, session lifecycle (START -> UPDATE -> STOP), zero/invalid GPS rejection (`(0,0)`, `NaN`, out-of-range).
- `tests/test_nearby_users.py`: Haversine/PostGIS radius calculations, nearby responder discovery, distance sorting.
- `tests/test_admin_security.py`: Role-based access control (RBAC), unauthorized token rejection, live statistics calculation from real database records.
- `tests/test_concurrency.py`: 10+ concurrent users triggering emergencies and live location streams simultaneously without data leakage or race conditions.

---

## 2. End-to-End User A → User B Verification

Follow these steps to test the real-world flow between two phones or browser tabs:

### Step 1: User A Starts Emergency / Live Location
1. Open the mobile app on Device A (`http://<HOST_IP>:8000/app/` or installed APK).
2. Login with phone `+919876543210` (OTP: `000000` in dev mode).
3. Tap **"HOLD / ACTIVATE EMERGENCY"** or **"SHARE LIVE LOCATION"**.
4. Device A displays:
   - 🚨 Emergency Active / 🟢 Live Location Active
   - Unique `Session ID` / `Alert ID`
   - Real-time GPS accuracy & "Last updated: X sec ago"

### Step 2: User B Discovers Nearby Emergency
1. Open the mobile app on Device B (`http://<HOST_IP>:8000/app/`).
2. Login with phone `+919876543211`.
3. Under **"Active Nearby Emergencies"**, User B automatically sees User A's incident:
   - User Name & Distance (e.g., `350 m away`)
   - GPS accuracy and update freshness (`Updated 2s ago`)

### Step 3: Navigation & Community Response
1. On Device B, click **"NAVIGATE"**:
   - Google Maps opens with directions to User A's latest valid GPS coordinates:
     `https://www.google.com/maps/dir/?api=1&destination=LAT,LONG`
2. On Device B, click **"I'M COMING"**:
   - Device B acknowledges the response.
   - Device A immediately updates: `🟢 Bhai Helper confirmed: I'M COMING`.

### Step 4: Admin Live Monitoring
1. Open Admin Panel at `http://<HOST_IP>:8000/admin`.
2. Login with `admin` / `BhaiSecureAdmin2026!`.
3. Verify:
   - Metric cards increment from real database state.
   - Leaflet map plots User A's real-time position marker.
   - Active responder count shows `1`.
   - Admin **"NAVIGATE"** button opens Google Maps to User A's coordinates.

### Step 5: Incident Resolution
1. On Device A, tap **"RESOLVE / STOP"**.
2. Device A ends the broadcast and closes the location stream.
3. Device B and Admin update in realtime:
   - Emergency card is removed from ACTIVE list.
   - Incident is archived in RESOLVED history.

---

## 3. Concurrency & Multi-User Isolation Test

To verify that multiple users never overwrite each other's sessions:
1. Open 3 separate incognito browser sessions (User A, User B, User C).
2. Start Live Location on User A (`SESSION_A`) and User C (`SESSION_C`).
3. Update User A's location coordinates.
4. Verify User B and Admin see distinct markers and independent data streams for User A and User C.
5. Stop `SESSION_A`; verify `SESSION_C` remains active and uninterrupted.

---

## 4. GPS & Coordinate Validation Rules

The backend and frontend enforce strict coordinate validation:
- **Null Island Rejection:** `(0.00000, 0.00000)` is strictly rejected with `422 Unprocessable Entity`.
- **Range Constraints:** Latitude must be in `[-90, 90]`, Longitude in `[-180, 180]`.
- **Stale Detection:** Locations with no updates for >30 seconds display `LOCATION STALE`.
- **Unavailable Fallback:** If GPS is denied, UI displays `LOCATION UNAVAILABLE` instead of fake/zero coordinates.
