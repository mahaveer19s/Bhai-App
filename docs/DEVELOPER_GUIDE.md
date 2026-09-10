# Bhai App Developer Guide & Decision Rationales

## 1. "Which Method and Why" — Key Technical Decisions

This section details the architectural choices made across the codebase, explaining what was chosen, alternative options considered, and why the chosen approach is optimal for a mission-critical emergency system.

---

### Decision 1: FastAPI + Asynchronous SQLAlchemy vs Node.js / Go
- **Chosen**: Python 3.12+ with FastAPI and async SQLAlchemy (`asyncpg`).
- **Why**:
  - FastAPI generates standards-compliant OpenAPI 3.1 documentation automatically.
  - Native Python `asyncio` handles thousands of concurrent WebSocket connections and lightweight 5-second location updates effortlessly.
  - Python's geospatial ecosystem (GeoAlchemy2, Shapely) provides seamless PostGIS integration without raw string concatenation vulnerabilities.
  - Pydantic v2 offers instant, high-speed validation for incoming GPS telemetry payloads.

---

### Decision 2: Pure Vanilla ES6 + Leaflet for Admin Console vs React / Next.js
- **Chosen**: Zero-dependency Vanilla HTML5 / Modern CSS / ES6 with Leaflet.js.
- **Why**:
  - **Zero Build Step**: No `node_modules`, npm dependencies, webpack/vite configs, or build pipeline vulnerabilities in the deployment container.
  - **Instant Load Time**: The administrative operator console loads in under 150ms on low-bandwidth emergency command terminals.
  - **Single Source of Truth**: Served directly as static files from FastAPI (`/admin`), completely eliminating CORS complexity and deployment desynchronization.
  - **Direct DOM Reactivity**: Smooth Leaflet marker animations and real-time DOM updates without the virtual DOM reconciliation overhead during high-frequency 5-second location updates.

---

### Decision 3: Dual-Rail Mesh: BLE 2.4GHz + WebSockets vs Cellular-Only
- **Chosen**: Hybrid Dual-Rail Dispatch (Direct BLE Advertising + Cloud WebSockets).
- **Why**:
  - In crowded environments, riots, natural disasters, or underground areas, cellular networks suffer total failure or signal blockages.
  - BLE 2.4GHz peer-to-peer advertising reaches surrounding phones within a 10-50 meter radius in under 300 milliseconds with zero internet connection.
  - When cellular connectivity is available, the cloud rail automatically broadcasts alerts to the central command center and users miles away.

---

### Decision 4: PostGIS Geography Types vs In-Memory Geometry / Haversine
- **Chosen**: PostgreSQL 16 with PostGIS `geography(Point, 4326)` and GIST spatial index, backed by an in-memory Haversine formula fallback.
- **Why**:
  - Earth is an ellipsoid; planar geometry calculations introduce severe distance errors over kilometers.
  - PostGIS `ST_DWithin` and `ST_Distance` on `geography` calculate geodesic distances accurately in meters natively at the database engine level.
  - The fallback Haversine implementation guarantees high availability even if the database is running in an initial recovery mode.

---

### Decision 5: Non-Blocking 5-Second Live Streaming vs WebRTC / Socket.IO
- **Chosen**: Lightweight HTTP POST streaming with WebSocket dispatch fan-out.
- **Why**:
  - WebRTC requires complex STUN/TURN infrastructure, high battery consumption, and complex ICE handshakes that fail behind carrier-grade NATs.
  - Socket.IO introduces proprietary protocol framing and compatibility issues with standard HTTP load balancers.
  - Clean HTTP POST `/api/live-location/update` every 5 seconds is stateless, battery-efficient, easily rate-limited, and enables WebSocket fan-out to admin consoles in real time.

---

### Decision 6: Scoped Multi-User Idempotency vs Global Key Hash
- **Chosen**: Tuple-scoped idempotency key validation: `(user_id, idempotency_key)`.
- **Why**:
  - A global dictionary or key store without user scoping would cause collisions if two independent devices generated similar sequence IDs.
  - User-scoped idempotency allows each user to safely retry failed network requests without blocking or deduplicating alerts from another user experiencing a simultaneous emergency.

---

## 2. Repository Directory Structure

```
bhaiProject/
├── backend/                         # FastAPI Backend Application
│   ├── app/
│   │   ├── api/                     # REST Routers
│   │   │   ├── admin.py             # Admin Dashboard & Auth Endpoints
│   │   │   ├── auth.py              # User Phone Auth & Tokens
│   │   │   ├── contacts.py          # Trusted Safety Contacts
│   │   │   ├── emergencies.py       # Emergency Alerts & Nearby Users
│   │   │   ├── live_location.py     # 5s Live Telemetry Engine
│   │   │   └── relay.py             # Store-and-Forward Offline Relay
│   │   ├── static/                  # Production Web Assets
│   │   │   ├── admin/               # Standalone Admin Radar Console
│   │   │   │   ├── index.html       # Admin UI Layout
│   │   │   │   ├── admin.css        # High-Performance Theme & Glows
│   │   │   │   └── admin.js         # Leaflet Radar & WS Client
│   │   │   └── landing/             # Public Landing & APK Download
│   │   │       ├── index.html       # Landing Showcase
│   │   │       ├── landing.css      # Hero & Features Styling
│   │   │       └── landing.js       # Dynamic Release Info Fetcher
│   │   ├── config.py                # Pydantic Settings & Defaults
│   │   ├── database.py              # Async SQLAlchemy Engine & Session
│   │   ├── deps.py                  # JWT Auth & Role Dependencies
│   │   ├── main.py                  # FastAPI App, WebSockets, Mounts
│   │   ├── models.py                # SQLAlchemy Data Models
│   │   ├── realtime.py              # WebSocket Mesh Connection Manager
│   │   ├── schemas.py               # Pydantic Request/Response Models
│   │   ├── security.py              # Password Hashing & JWT Minting
│   │   └── services/                # Background Services & Retention
│   ├── tests/                       # Automated Test Suite (Pytest)
│   │   ├── test_admin_security.py   # RBAC & Admin Access Tests
│   │   ├── test_concurrency.py      # Multi-user & Stream Concurrency
│   │   ├── test_live_location.py    # 5s Stream Lifecycle Tests
│   │   ├── test_nearby_users.py     # PostGIS / Haversine Radius Tests
│   │   └── test_api.py              # Base System Verification
│   └── requirements.txt             # Python Package Dependencies
│
├── bhai_app/                        # Flutter Mobile Application
│   ├── android/                     # Android Native Platform Code
│   │   └── app/src/main/kotlin/.../
│   │       └── MainActivity.kt      # Native BLE & Maps MethodChannel
│   ├── lib/
│   │   ├── core/
│   │   │   ├── services/            # Bluetooth, API, Emergency Services
│   │   │   │   ├── api_client.dart
│   │   │   │   ├── bluetooth_service.dart
│   │   │   │   └── emergency_service.dart
│   │   │   └── theme/               # Colors & Typography
│   │   └── features/
│   │       ├── home/presentation/   # SOS Screen & Action Controls
│   │       └── emergency/           # Alert Presentation & Responders
│   └── pubspec.yaml                 # Flutter Dependencies
│
├── database/
│   └── schema.sql                   # Reference PostgreSQL DDL Schema
├── docs/                            # Comprehensive Documentation
│   ├── ARCHITECTURE.md              # Architecture & Data Flows
│   ├── DEVELOPER_GUIDE.md           # Engineering Guide & Rationales
│   ├── API.md                       # Complete API Reference
│   └── DEPLOYMENT.md                # Docker & Render Runbook
├── bhai_app.apk                     # Release APK Binary (Served directly)
├── Dockerfile                       # Production Container Definition
├── docker-compose.yml               # Local Multi-Service Orchestration
└── .env.example                     # Environment Configuration Template
```

---

## 3. Development Setup Instructions

### Prerequisites
- Python 3.12+ (or Python 3.13)
- Flutter 3.22+
- PostgreSQL 16 with PostGIS extension (or Docker)

### Backend Local Setup
```bash
# Navigate to backend
cd backend

# Create and activate virtual environment
python -m venv .venv
# On Windows PowerShell:
.\.venv\Scripts\Activate.ps1
# On macOS/Linux:
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run automated tests
pytest -v

# Start development server
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### Mobile App Local Setup
```bash
cd bhai_app

# Install dependencies
flutter pub get

# Run static analysis
flutter analyze

# Launch on connected Android device or emulator
flutter run --dart-define=BHAI_API_URL=http://10.0.2.2:8000
```

---

## 4. Coding Standards & Conventions

1. **Strict Type Annotations**: All Python functions must specify explicit input argument types and return type annotations.
2. **Asynchronous I/O**: Use `async`/`await` for all database interactions and network dispatches to prevent event-loop blocking.
3. **Graceful Degradation**: Core features must degrade gracefully (e.g., in-memory fallback for PostGIS when offline, BLE mesh fallback when disconnected from cellular).
4. **No Destructive Global Resets**: Never implement global clear endpoints that wipe data belonging to all users. Every state transition must be scoped to an individual record.
5. **No Placeholders**: Never commit mock responses, fake credentials, or TODO placeholders into production paths.
