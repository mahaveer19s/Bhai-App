# BHAI Codebase Map & Component Reference

This document indexes the core components, files, inputs, outputs, and architectural responsibilities across the BHAI emergency platform.

---

## 1. Directory Structure Overview

```text
bhaiProject/
├── backend/                  # FastAPI Application & Database Gateway
│   ├── app/
│   │   ├── api/              # REST Endpoints (auth, emergencies, live_location, admin)
│   │   ├── models.py         # SQLAlchemy ORM Database Entities
│   │   ├── schemas.py        # Pydantic Request/Response DTOs & Validators
│   │   ├── database.py       # Engine & Session Management
│   │   ├── realtime.py       # WebSocket Connection Mesh & Event Broadcaster
│   │   ├── security.py       # JWT & HMAC Cryptography
│   │   ├── deps.py           # Dependency Injection & Token Parsers
│   │   └── static/           # Standalone Admin Radar & Landing Portals
│   ├── tests/                # Automated Pytest Suite (Concurrency, Live Location, RBAC)
│   └── requirements.txt      # Python Dependencies
├── bhai_app/                 # Flutter Cross-Platform Client (Android, iOS, Web)
│   ├── lib/
│   │   ├── core/             # Routing, Theme, Services, Storage, Protocol
│   │   │   ├── services/     # EmergencyService, LocationService, BluetoothService
│   │   ├── features/         # Modular Screen Features (emergency, home, map, settings)
│   │   └── main.dart         # Client Entry Point & State Injection
│   └── android/              # Native Android Wrapper & Foreground BLE Service
├── bhai_admin/               # Flutter Web Admin Operations Console
├── database/                 # PostgreSQL & PostGIS Schema Definitions
│   └── schema.sql            # Master DDL with Spatial Indexes
├── docs/                     # Architecture, API, Security & Deployment Guides
├── tests/load/               # Synthetic Load Testing Scripts (Locust / k6)
├── Dockerfile                # Root Multi-Service Docker Build
├── docker-compose.yml        # Local Development Stack
└── bhai_app.apk              # Compiled Android Release Binary
```

---

## 2. Key Component Index

### 🚀 Backend Core

#### [`backend/app/main.py`](file:///d:/DreamProject/bhaiProject/backend/app/main.py)
- **Purpose:** FastAPI entry point, lifespan initialization, CORS setup, WebSocket mount points, and static file hosting.
- **Inputs:** HTTP requests, WebSocket handshakes, environment settings.
- **Outputs:** JSON responses, binary APK streams, real-time WebSocket feeds.

#### [`backend/app/api/emergencies.py`](file:///d:/DreamProject/bhaiProject/backend/app/api/emergencies.py)
- **Purpose:** Manages the full emergency lifecycle (`CREATED` → `ACTIVE` → `ACKNOWLEDGED` → `RESOLVED` / `CANCELLED`), idempotent emergency triggers, and community responder registrations (`"I'M COMING"`).
- **Inputs:** `EmergencyCreate` DTOs with validated coordinates, bearer tokens.
- **Outputs:** `EmergencyOut` incident status records, push dispatch tasks.

#### [`backend/app/api/live_location.py`](file:///d:/DreamProject/bhaiProject/backend/app/api/live_location.py)
- **Purpose:** Non-blocking 5-second coordinate streaming gateway.
- **Inputs:** `LiveLocationStart`, `LiveLocationUpdate` (lat/lng/accuracy), `session_id`.
- **Outputs:** `LiveLocationSessionOut` with active tracking metadata.

#### [`backend/app/realtime.py`](file:///d:/DreamProject/bhaiProject/backend/app/realtime.py)
- **Purpose:** Thread-safe, non-blocking in-memory WebSocket manager routing live location breadcrumbs and emergency triggers to authorized responders and admin listeners.

---

### 📱 Mobile Client (bhai_app)

#### [`bhai_app/lib/core/services/emergency_service.dart`](file:///d:/DreamProject/bhaiProject/bhai_app/lib/core/services/emergency_service.dart)
- **Purpose:** Coordinates emergency activation, audio siren triggers, encrypted local queueing, and network dispatch.

#### [`bhai_app/lib/core/services/location_service.dart`](file:///d:/DreamProject/bhaiProject/bhai_app/lib/core/services/location_service.dart)
- **Purpose:** Manages high-accuracy GPS streams, geofencing, coordinate validation, and background location lifecycle.

#### [`bhai_app/lib/core/services/bluetooth_service.dart`](file:///d:/DreamProject/bhaiProject/bhai_app/lib/core/services/bluetooth_service.dart)
- **Purpose:** Android Native BLE mesh advertiser/scanner fallback for offline peer-to-peer distress beacons.
