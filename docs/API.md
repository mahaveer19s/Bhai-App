# Bhai App API Reference Manual

The Bhai App backend exposes high-performance REST APIs and real-time WebSockets for emergency dispatch, live location telemetry streaming, nearby peer discovery, and administrative management.

- **Base URL**: `https://<domain>/api` (also supports top-level paths for backwards compatibility)
- **Authentication**: `Bearer <JWT_TOKEN>` in `Authorization` header
- **Formats**: `application/json`

---

## 1. Authentication Endpoints

### 1.1 Admin Authentication
#### `POST /api/admin/login`
Authenticates a central operator and issues a high-privilege JWT token.

- **Request Body**:
```json
{
  "email": "admin@bhai.app",
  "password": "BhaiSecureAdmin2026!"
}
```
- **Response `200 OK`**:
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "bearer",
  "role": "ADMIN"
}
```
- **Errors**:
  - `401 Unauthorized`: Invalid email or password.

---

### 1.2 Request Mobile Phone OTP
#### `POST /api/auth/otp/request`
Sends a verification OTP to the specified mobile phone number.

- **Request Body**:
```json
{
  "phone_number": "+919876543210"
}
```
- **Response `200 OK`**:
```json
{
  "message": "OTP sent successfully",
  "expires_in_seconds": 300
}
```

---

### 1.3 Verify OTP & Authenticate
#### `POST /api/auth/otp/verify`
Validates the received OTP code and issues a mobile client JWT token.

- **Request Body**:
```json
{
  "phone_number": "+919876543210",
  "code": "123456"
}
```
- **Response `200 OK`**:
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "bearer"
}
```

---

## 2. Emergency Management Endpoints

### 2.1 Trigger Emergency Alert
#### `POST /api/emergency/alert` (or `/emergencies`)
Triggers an emergency incident, stores the starting GPS coordinates, and dispatches real-time alerts to nearby users and the admin command center.

- **Headers**: `Authorization: Bearer <USER_TOKEN>`
- **Request Body**:
```json
{
  "idempotency_key": "bhai-alert-unique-nonce-12345",
  "latitude": 28.6273,
  "longitude": 77.3725,
  "accuracy": 4.5,
  "recorded_at": "2026-09-10T16:30:00Z",
  "network_status": "ONLINE",
  "device_status": {
    "source": "mobile_sos"
  }
}
```
- **Response `200 OK`**:
```json
{
  "id": "7b8e5c3e-9092-4f11-9a7c-619f71c4a012",
  "status": "ACTIVE",
  "latitude": 28.6273,
  "longitude": 77.3725,
  "triggered_at": "2026-09-10T16:30:00Z",
  "dispatched_helpers": 4
}
```

---

### 2.2 Acknowledge Emergency
#### `POST /api/emergency/{emergency_id}/acknowledge`
A nearby volunteer marks that they are responding to the emergency.

- **Headers**: `Authorization: Bearer <HELPER_TOKEN>`
- **Response `200 OK`**:
```json
{
  "status": "ACKNOWLEDGED",
  "helper_user_id": "8f3b23c1-05cb-42a9-a9a3-5c8fe2b1f819",
  "acknowledged_at": "2026-09-10T16:30:05Z"
}
```

---

### 2.3 Resolve Emergency
#### `POST /api/emergency/{emergency_id}/resolve` (or `/emergencies/{id}/end`)
Marks the emergency incident as successfully resolved. Can only be invoked by the creator or an administrator.

- **Headers**: `Authorization: Bearer <TOKEN>`
- **Request Body** (optional):
```json
{
  "reason": "RESOLVED_BY_USER"
}
```
- **Response `200 OK`**:
```json
{
  "id": "7b8e5c3e-9092-4f11-9a7c-619f71c4a012",
  "status": "RESOLVED",
  "ended_at": "2026-09-10T16:35:00Z"
}
```

---

### 2.4 Cancel Emergency
#### `POST /api/emergency/{emergency_id}/cancel`
Cancels an emergency triggered accidentally.

- **Headers**: `Authorization: Bearer <TOKEN>`
- **Request Body**:
```json
{
  "reason": "FALSE_ALARM"
}
```
- **Response `200 OK`**:
```json
{
  "id": "7b8e5c3e-9092-4f11-9a7c-619f71c4a012",
  "status": "CANCELLED"
}
```

---

## 3. 5-Second Live Location Telemetry Endpoints

### 3.1 Start Live Location Session
#### `POST /api/live-location/start`
Initializes a new independent live telemetry stream.

- **Headers**: `Authorization: Bearer <USER_TOKEN>`
- **Request Body**:
```json
{
  "emergency_id": "7b8e5c3e-9092-4f11-9a7c-619f71c4a012",
  "latitude": 28.6273,
  "longitude": 77.3725,
  "accuracy": 4.0
}
```
- **Response `200 OK`**:
```json
{
  "id": "1d8b725c-e6bf-46ce-a19f-ecff6796c021",
  "user_id": "e932b13e-324c-4112-990a-f0b7c1266e77",
  "emergency_id": "7b8e5c3e-9092-4f11-9a7c-619f71c4a012",
  "status": "ACTIVE",
  "update_interval_seconds": 5,
  "created_at": "2026-09-10T16:30:00Z",
  "updated_at": "2026-09-10T16:30:00Z"
}
```

---

### 3.2 Post Periodic Location Update
#### `POST /api/live-location/update`
Invoked every 5 seconds by the mobile client while live sharing is active.

- **Headers**: `Authorization: Bearer <USER_TOKEN>`
- **Request Body**:
```json
{
  "session_id": "1d8b725c-e6bf-46ce-a19f-ecff6796c021",
  "latitude": 28.6274,
  "longitude": 77.3728,
  "accuracy": 3.8,
  "altitude": 210.5,
  "heading": 85.0,
  "speed": 1.2
}
```
- **Response `200 OK`**:
```json
{
  "id": "a1f2b3c4-d5e6-47f8-9a0b-1c2d3e4f5a6b",
  "session_id": "1d8b725c-e6bf-46ce-a19f-ecff6796c021",
  "latitude": 28.6274,
  "longitude": 77.3728,
  "accuracy": 3.8,
  "altitude": 210.5,
  "heading": 85.0,
  "speed": 1.2,
  "recorded_at": "2026-09-10T16:30:05Z"
}
```

---

### 3.3 Stop Live Location Session
#### `POST /api/live-location/stop`
Terminates the live location stream.

- **Headers**: `Authorization: Bearer <USER_TOKEN>`
- **Request Body**:
```json
{
  "session_id": "1d8b725c-e6bf-46ce-a19f-ecff6796c021"
}
```
- **Response `200 OK`**:
```json
{
  "id": "1d8b725c-e6bf-46ce-a19f-ecff6796c021",
  "status": "STOPPED",
  "message": "Live location streaming stopped successfully"
}
```

---

## 4. Discovery & Geospatial Endpoints

### 4.1 Discover Nearby Users
#### `GET /api/nearby-users`
Queries PostGIS for available Bhai App devices within a geographic radius.

- **Headers**: `Authorization: Bearer <USER_TOKEN>`
- **Query Parameters**:
  - `latitude` (float, required): Caller's latitude
  - `longitude` (float, required): Caller's longitude
  - `radius_meters` (int, default: 2000, max: 10000): Search radius
- **Response `200 OK`**:
```json
[
  {
    "user_id": "3f9c2d1b-...",
    "distance_meters": 342.5,
    "latitude": 28.6291,
    "longitude": 77.3740,
    "last_seen": "2026-09-10T16:29:45Z"
  }
]
```

---

## 5. Administrative Endpoints

### 5.1 Dashboard Overview
#### `GET /api/admin/dashboard`
Returns live metrics, incident volume, and active stream counts.

- **Headers**: `Authorization: Bearer <ADMIN_TOKEN>`
- **Response `200 OK`**:
```json
{
  "total_emergencies": 128,
  "active_emergencies": 3,
  "active_live_streams": 2,
  "active_helpers": 47,
  "recent_incidents": []
}
```

---

### 5.2 List Active Emergencies
#### `GET /api/admin/emergencies?status=ACTIVE`
Retrieves full incident details for the admin radar view.

- **Headers**: `Authorization: Bearer <ADMIN_TOKEN>`
- **Response `200 OK`**: List of emergency incident objects.

---

### 5.3 List Active Live Streams
#### `GET /api/admin/live-locations`
Retrieves all currently active 5-second live location streams with latest coordinates and telemetry history.

- **Headers**: `Authorization: Bearer <ADMIN_TOKEN>`
- **Response `200 OK`**: List of active session objects.

---

## 6. Realtime WebSockets

### 6.1 Admin Command Center Socket
#### `WebSocket /ws/admin?token=<ADMIN_TOKEN>`
Pushes instant updates to the admin radar console:
- `EMERGENCY_DISPATCH`: New emergency alert triggered
- `LIVE_LOCATION_STREAM`: 5-second GPS update emitted by an active stream
- `STATUS_UPDATE`: Emergency resolved, acknowledged, or cancelled

### 6.2 Incident Room Socket
#### `WebSocket /ws/emergencies/{emergency_id}?token=<USER_OR_HELPER_TOKEN>`
Bi-directional channel for chat, distance updates, and helper proximity.
