# BHAI Production Deployment & Cloud Setup Guide

## 1. Cloud Infrastructure
- **Web Service**: Render / Docker / Linux VPS running Python 3.12+ / FastAPI / Uvicorn.
- **Database**: PostgreSQL 16+ with PostGIS geospatial extension enabled (`CREATE EXTENSION IF NOT EXISTS postgis;`).
- **Flutter Web Simulator**: Hosted statically under `/app/` with `<base href="/app/">`.
- **Admin Command Center**: Hosted statically under `/admin/`.

---

## 2. Environment Variables Specification

| Variable Name | Scope | Description | Default / Example |
| :--- | :--- | :--- | :--- |
| `DATABASE_URL` | **SERVER ONLY** | PostgreSQL connection URI | `postgresql+asyncpg://bhai:secret@localhost:5432/bhai` |
| `JWT_SECRET_KEY` | **SERVER ONLY** | Secret for signing auth tokens | (Min 32-char high-entropy string) |
| `ADMIN_USERNAME` | **SERVER ONLY** | Administrator login username | `admin` |
| `ADMIN_PASSWORD` | **SERVER ONLY** | Administrator login password | (Configured securely) |
| `APK_DOWNLOAD_URL`| Public | Direct URL to download signed APK | `/download/bhai_app.apk` |

---

## 3. Render 1-Click Deployment
Deploy easily using `render.yaml` with automatic PostgreSQL dialect normalization:
```yaml
services:
  - type: web
    name: bhai-emergency-platform
    env: python
    buildCommand: pip install -r backend/requirements.txt
    startCommand: cd backend && uvicorn app.main:app --host 0.0.0.0 --port $PORT
```
