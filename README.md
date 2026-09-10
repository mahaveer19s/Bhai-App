# BHAI — Emergency Assistance & Realtime Community Response

> **"Get help from people nearby when you need it most."**

BHAI is an asynchronous, privacy-first emergency assistance and live-location streaming platform. It connects people in distress with nearby opted-in community helpers, trusted contacts, and emergency operations teams in real time.

---

## 🌟 Key Features

- 🚨 **Emergency Alert Trigger:** Fast, idempotent emergency activation with debounce protection and local encrypted queueing.
- 📍 **5-Second Live Location Streaming:** Independent non-blocking session lifecycle (`START` → `UPDATE` → `STOP`) streaming coordinate breadcrumbs every 5 seconds.
- 🧭 **Direct Navigation (User A → User B):** Dynamic Google Maps directions to the victim's latest valid GPS coordinates.
- 🟢 **Community Responders ("I'M COMING"):** Independent helper acknowledgements that increment responder metrics in real time.
- 🛡️ **Admin Operations Radar:** Separate authenticated dashboard (`/admin`) featuring real-time OpenStreetMap tracking and database metrics.
- 📡 **Bluetooth Mesh Fallback:** Native Android BLE advertiser/scanner for short-range distress beacons when cellular data is offline.
- 🚫 **Strict GPS Validation:** Strict rejection of Null Island `(0.00000, 0.00000)`, `NaN`, and malformed coordinate inputs.
- 📱 **Android APK Distribution:** Integrated endpoint (`/download/bhai_app.apk`) for immediate over-the-air installation.

---

## 🏗️ Architecture & Technology Stack

```text
[Mobile App / Web Simulator] ─── (REST / WebSockets) ───> [FastAPI Backend] ───> [PostgreSQL / PostGIS]
                                                                  │
                                                      [Admin Operations Radar]
```

- **Backend:** FastAPI (Python 3.13), SQLAlchemy 2.0 Async, GeoAlchemy2, Uvicorn.
- **Database:** PostgreSQL 16+ with PostGIS spatial extension.
- **Mobile / Web:** Flutter (Dart) with native Android foreground service & BLE mesh support.
- **Admin Dashboard:** Standalone Leaflet / OpenStreetMap operations radar & Flutter Web.
- **Deployment:** Docker, Docker Compose, Render.

---

## 📂 Repository Structure

```text
bhaiProject/
├── backend/                  # FastAPI Application & Database Gateway
│   ├── app/                  # API routers, models, schemas, database engine, realtime mesh
│   ├── tests/                # Automated pytest suite (concurrency, live stream, RBAC)
│   └── requirements.txt      # Python dependencies
├── bhai_app/                 # Flutter mobile & web application
│   ├── lib/                  # Screens, services (emergency, location, bluetooth)
│   └── android/              # Native Android foreground service & BLE advertiser
├── bhai_admin/               # Flutter web admin operations console
├── database/                 # PostgreSQL / PostGIS DDL schema
├── docs/                     # Comprehensive architecture, API, security, deployment guides
├── tests/load/               # Locust & k6 synthetic stress test scripts
├── .github/                  # CI workflows, issue templates, PR templates
├── .env.example              # Environment configuration template
├── Dockerfile                # Multi-service production Docker container definition
├── docker-compose.yml        # Development multi-container stack
└── bhai_app.apk              # Release Android binary
```

---

## ⚙️ Quick Local Setup

### 1. Clone & Configure Environment
```bash
git clone https://github.com/mahaveer19s/Bhai-App.git
cd Bhai-App
cp .env.example .env
```

### 2. Start Backend & Database
```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### 3. Access Interfaces
- **📱 Web Simulator:** `http://localhost:8000/app/`
- **🛡️ Admin Radar:** `http://localhost:8000/admin` *(User: `admin` / Pass: `BhaiSecureAdmin2026!`)*
- **🌐 Public Landing:** `http://localhost:8000/`
- **⚡ Swagger API Docs:** `http://localhost:8000/docs`

---

## 🧪 Running Tests

### Automated Pytest Suite
```powershell
cd backend
pytest -v
```
*(All 21 unit, concurrency, live stream, and security test cases pass).*

### Synthetic Load Tests (Locust)
```bash
locust -f tests/load/locustfile.py --host=http://localhost:8000
```

---

## 🚀 Deployment to Render

1. Create a **PostgreSQL** instance with PostGIS enabled on Render.
2. Create a **Web Service** pointing to the repository:
   - **Root Directory:** `backend`
   - **Build Command:** `pip install -r requirements.txt`
   - **Start Command:** `uvicorn app.main:app --host 0.0.0.0 --port $PORT`
   - **Health Check Path:** `/health`
3. Configure environment variables in Render (see [`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md)).

---

## 📖 Detailed Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — System design & state machines
- [`docs/API.md`](docs/API.md) — Complete REST & WebSocket API specification
- [`docs/DEVELOPER_GUIDE.md`](docs/DEVELOPER_GUIDE.md) — Design choices & developer workflows
- [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) — Step-by-step production deployment
- [`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md) — Environment variable dictionary
- [`docs/SECURITY.md`](docs/SECURITY.md) — Authentication, RBAC, and location privacy
- [`docs/CONCURRENCY.md`](docs/CONCURRENCY.md) — Multi-user isolation & idempotency
- [`docs/SCALABILITY.md`](docs/SCALABILITY.md) — Ingestion benchmarks & capacity planning
- [`docs/TESTING.md`](docs/TESTING.md) — Multi-phone manual & automated test guide
- [`docs/PRODUCTION_READINESS.md`](docs/PRODUCTION_READINESS.md) — Feature audit matrix

