# BHAI Environment Variables Specification

This document details every environment variable used across the BHAI platform, distinguishing public frontend variables from server-only secrets.

---

## 1. Environment Variables Overview

| Variable | Service | Classification | Purpose & Description | Default / Example |
| :--- | :--- | :--- | :--- | :--- |
| `DATABASE_URL` | Backend | **SECRET** | PostgreSQL + PostGIS async connection string. | `postgresql+asyncpg://user:pass@host:5432/bhai` |
| `JWT_SECRET` | Backend | **SECRET** | 256-bit cryptographically secure key for signing access tokens. | *(32+ char random string)* |
| `OTP_HMAC_SECRET` | Backend | **SECRET** | Cryptographic HMAC secret for hashing and verifying OTP challenges. | *(32+ char random string)* |
| `ADMIN_EMAIL` | Backend | Public / Config | Default admin account email for incident console access. | `admin@bhai.app` |
| `ADMIN_PASSWORD` | Backend | **SECRET** | Default admin account password (must be rotated in production). | *(Strong password)* |
| `ENVIRONMENT` | Backend | Config | Runtime mode (`development`, `staging`, `production`). | `production` |
| `CORS_ORIGINS` | Backend | Config | Comma-separated list of allowed client origins. | `https://bhai.app,https://admin.bhai.app` |
| `EMERGENCY_RADIUS_METERS` | Backend | Config | Radius in meters to query nearby active helpers. | `2000` |
| `EMERGENCY_NUMBER` | Backend | Config | National emergency helpline number. | `112` |
| `LOCATION_RETENTION_DAYS`| Backend | Config | Days before resolved location breadcrumbs are purged. | `90` |
| `LIVE_LOCATION_INTERVAL_SECONDS` | Backend / App | Config | Frequency of live GPS coordinate updates. | `5` |
| `LIVE_LOCATION_SESSION_TIMEOUT_MINUTES` | Backend | Config | Timeout after which inactive sessions are marked expired. | `60` |
| `APK_VERSION` | Backend | Public | Version number displayed on landing page and version endpoint. | `1.2.0` |
| `APK_SIZE_MB` | Backend | Public | File size of the release APK displayed in megabytes. | `49.8` |
| `APK_FILE_PATH` | Backend | Config | Local filesystem path to the compiled APK binary. | `./bhai_app.apk` |
| `APK_DOWNLOAD_URL` | Backend | Public | Download endpoint or CDN URL for the Android APK. | `/download/bhai_app.apk` |
| `DEV_OTP_CODE` | Backend | Dev Only | Fixed OTP bypass for local unit/integration tests (ignored in prod). | `000000` |
| `FIREBASE_CREDENTIALS_PATH` | Backend | **SECRET** | Path to Firebase service account JSON for FCM push alerts. | `/etc/secrets/firebase.json` |
| `TWILIO_ACCOUNT_SID` | Backend | **SECRET** | Twilio account SID for production SMS dispatches. | *(Twilio SID)* |
| `TWILIO_AUTH_TOKEN` | Backend | **SECRET** | Twilio auth token for SMS authentication. | *(Twilio Token)* |
| `TWILIO_FROM_NUMBER` | Backend | Config | Verified sender phone number for SMS emergency alerts. | `+1234567890` |
| `BHAI_API_URL` | Mobile / Admin | Public | Base HTTP/WebSocket URL to the running backend service. | `https://api.bhai.app` |

---

## 2. Security Boundaries: Client vs Server

### 🔒 Server-Only Secrets
The following variables **MUST NEVER** be bundled into client applications or committed to source control:
- `DATABASE_URL`
- `JWT_SECRET`
- `OTP_HMAC_SECRET`
- `ADMIN_PASSWORD`
- `FIREBASE_CREDENTIALS_PATH`
- `TWILIO_AUTH_TOKEN`

### 🌐 Public Client Variables
The following variables are safe for client-side inclusion (e.g. via `--dart-define` or public build config):
- `BHAI_API_URL`
- `APK_VERSION`
- `APK_DOWNLOAD_URL`
