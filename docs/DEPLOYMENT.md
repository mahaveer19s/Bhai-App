# Bhai App Deployment Runbook

This guide covers deployment options for **Bhai App**, including local development with Docker Compose and production cloud hosting on **Render** with managed PostgreSQL and PostGIS.

---

## 1. Quick Start: Local Deployment with Docker Compose

The fastest way to spin up the entire production environment locally is with Docker Compose.

```bash
# 1. Clone the repository and enter directory
cd bhaiProject

# 2. Copy the environment template
cp .env.example .env

# 3. Start PostgreSQL with PostGIS and the FastAPI backend
docker compose up --build -d

# 4. Verify running containers
docker compose ps

# 5. Check API health
curl http://localhost:8000/health
curl http://localhost:8000/ready
```

### Accessing Local Services
- **Public Landing & APK Download**: `http://localhost:8000/`
- **Admin Command Center**: `http://localhost:8000/admin`
  - Default Email: `admin@bhai.app`
  - Default Password: `BhaiSecureAdmin2026!`
- **Swagger Interactive API Docs**: `http://localhost:8000/docs`

---

## 2. Production Deployment on Render

Render provides managed PostgreSQL and Docker-based Web Services with automatic SSL certificates and continuous deployment from Git.

### Step 2.1: Provision Managed PostgreSQL with PostGIS
1. Navigate to your [Render Dashboard](https://dashboard.render.com).
2. Click **New +** -> **PostgreSQL**.
3. Configure the database:
   - **Name**: `bhai-production-db`
   - **Database**: `bhai`
   - **User**: `bhai_user`
   - **Region**: Select your preferred region (e.g., Singapore or Frankfurt).
   - **Plan**: Starter or Standard.
4. Once provisioned, connect to your database via psql or the Render Shell and enable the PostGIS extension:
   ```sql
   CREATE EXTENSION IF NOT EXISTS postgis;
   ```
5. Copy the **Internal Database URL** (`postgresql://...`).
   *Note: Modify the driver prefix to `postgresql+asyncpg://` for async SQLAlchemy in your environment variable.*

---

### Step 2.2: Deploy FastAPI Web Service
1. In Render, click **New +** -> **Web Service**.
2. Connect your Git repository.
3. Configure the Web Service:
   - **Name**: `bhai-api`
   - **Environment**: `Docker`
   - **Dockerfile Path**: `./Dockerfile`
   - **Docker Context**: `.`
   - **Region**: Same region as your database.
   - **Plan**: Starter or Standard.
4. Set the **Health Check Path** to `/health`.
5. Under **Environment Variables**, configure the following:

| Key | Example Value | Description |
|---|---|---|
| `DATABASE_URL` | `postgresql+asyncpg://bhai_user:password@dpg-xxx:5432/bhai` | PostGIS connection string with `asyncpg` |
| `ADMIN_EMAIL` | `admin@bhai.app` | Email for admin radar login |
| `ADMIN_PASSWORD` | `<secure-generated-password>` | Password for admin login |
| `JWT_SECRET` | `<32+-random-characters>` | Secret used to sign authentication tokens |
| `OTP_HMAC_SECRET` | `<32+-random-characters>` | Secret used for OTP signature verification |
| `ENVIRONMENT` | `production` | Deployment environment |
| `CORS_ORIGINS` | `*` | Allowed CORS origins |
| `EMERGENCY_RADIUS_METERS`| `2000` | Discovery radius in meters |
| `LIVE_LOCATION_INTERVAL_SECONDS` | `5` | Live location streaming frequency |
| `APK_VERSION` | `1.2.0` | Mobile app release version |
| `APK_SIZE_MB` | `49.8` | Release APK size |
| `APK_DOWNLOAD_URL` | `/download/bhai_app.apk` | Or external CDN URL |

6. Click **Create Web Service**. Render will build the container, start the service, and verify the `/health` check.

---

## 3. Database Schema Initialization & Migrations

The application automatically executes database schema initialization and table creation on startup via the FastAPI `lifespan` handler in `backend/app/main.py`:
```python
async with engine.begin() as connection:
    await connection.execute(text("CREATE EXTENSION IF NOT EXISTS postgis"))
    await connection.run_sync(Base.metadata.create_all)
```

To manually apply the schema from `database/schema.sql`:
```bash
psql "$DATABASE_URL" -f database/schema.sql
```

---

## 4. Production Security Checklist

- [x] **Secure HTTPS & WSS**: Render automatically provisions TLS certificates for all HTTP and WebSocket connections.
- [x] **Strict Admin RBAC**: Unauthenticated access to `/api/admin/*` returns `401 Unauthorized`. Non-admin accounts receive `403 Forbidden`.
- [x] **Session Isolation**: Every live location stream has a unique UUIDv4 `session_id`. Users can only modify their own streams.
- [x] **Scoped Idempotency**: Idempotency keys are scoped per user to prevent cross-user collisions.
- [x] **Automated Data Retention**: Expired location records older than 90 days are purged automatically.
- [x] **Rate Limiting**: Critical authentication and alert endpoints are protected via `slowapi` rate limiters.
- [x] **No Hardcoded Secrets**: Secrets are read from environment variables via Pydantic Settings.

---

## 5. Monitoring & Operational Health Checks

- **Liveness Probe**: `GET /health`
  - Returns `{"status": "ok"}`
  - Used by Render, Kubernetes, and AWS ALB to verify container responsiveness.
- **Readiness Probe**: `GET /ready`
  - Returns `{"status": "ready", "database": "connected"}`
  - Verifies that PostgreSQL is actively responding to queries.
