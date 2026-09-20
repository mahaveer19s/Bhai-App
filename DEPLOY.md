# Production Deployment & Operations Manual — BHAI

This document provides a step-by-step, reproducible deployment guide for the **BHAI Emergency Assistance Platform** on production infrastructure, including standalone Linux Virtual Private Servers (VPS), Docker containers, and Cloud Platforms (e.g., Render / Supabase).

---

## 🏗️ Architecture Deployment Overview

```text
[ Internet / Mobile Clients ]
             │
      (HTTPS / 443 & WSS)
             ▼
[ Reverse Proxy / TLS Termination (Nginx / Caddy / Cloudflare) ]
             │
       (HTTP / 8000)
             ▼
[ FastAPI Application (Uvicorn Async ASGI) ]
        │                  │
        ▼                  ▼
[ PostgreSQL 16 + PostGIS ]  [ Local Memory / Async Event Bus ]
```

---

## 📋 System Prerequisites

| Component | Minimum Requirement | Recommended Production |
| :--- | :--- | :--- |
| **Operating System** | Ubuntu 22.04 LTS / Debian 12 | Ubuntu 24.04 LTS |
| **Compute** | 1 vCPU, 1 GB RAM | 2+ vCPU, 4+ GB RAM |
| **Storage** | 10 GB SSD | 50+ GB NVMe SSD with automated backups |
| **Python** | Python 3.11+ | Python 3.13 |
| **Database** | PostgreSQL 15+ with PostGIS | Managed PostgreSQL 16 with PostGIS |
| **TLS / SSL** | Valid domain name with Let's Encrypt | Automated ACME TLS 1.3 |

---

## 🔐 Environment Variables & Configuration

Create a production `.env` file based on `.env.example`.

```ini
# ==============================================================================
# DATABASE (PostgreSQL with PostGIS)
# ==============================================================================
DATABASE_URL=postgresql+asyncpg://bhai_admin:STRONG_DB_PASSWORD@127.0.0.1:5432/bhai_production

# ==============================================================================
# SECURITY SECRETS (Generate with: openssl rand -hex 32)
# ==============================================================================
JWT_SECRET=8f92a14b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f
OTP_HMAC_SECRET=1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b

# ==============================================================================
# ADMINISTRATIVE COMMAND CENTER
# ==============================================================================
ADMIN_USERNAME=admin@bhai.org
ADMIN_PASSWORD=STRONG_ADMIN_PASSWORD_2026!

# ==============================================================================
# NETWORK & PROXY HARDENING
# ==============================================================================
ENVIRONMENT=production
CORS_ORIGINS=https://app.bhai.org,https://admin.bhai.org
TRUSTED_PROXIES=127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12

# ==============================================================================
# OPERATIONAL POLICIES
# ==============================================================================
EMERGENCY_RADIUS_METERS=2000
EMERGENCY_NUMBER=112
LOCATION_RETENTION_DAYS=90
LIVE_LOCATION_INTERVAL_SECONDS=5

# ==============================================================================
# RELEASE METADATA & APK DISTRIBUTION
# ==============================================================================
APK_VERSION=1.2.0
APK_SIZE_MB=45.3 MB
APK_FILE_PATH=/opt/bhai/bhai_app.apk
APK_DOWNLOAD_URL=/download/bhai_app.apk
```

---

## 🚀 Deployment Option 1: Docker Compose (Recommended)

### 1. Clone & Set Up Configuration
```bash
git clone https://github.com/mahaveer19s/Bhai-App.git /opt/bhai
cd /opt/bhai
cp .env.example .env
# Edit .env with production passwords
nano .env
```

### 2. Build & Launch Containers
```bash
docker-compose up -d --build
```

### 3. Verify Container Health
```bash
docker-compose ps
curl -f http://localhost:8000/health
curl -f http://localhost:8000/ready
```

---

## 🌐 Deployment Option 2: Linux VPS (Systemd + Nginx Reverse Proxy)

### 1. System Package Installation
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3 python3-venv python3-pip postgresql postgresql-contrib postgis nginx certbot python3-certbot-nginx
```

### 2. PostgreSQL & PostGIS Setup
```bash
sudo -u postgres psql -c "CREATE DATABASE bhai_production;"
sudo -u postgres psql -c "CREATE USER bhai_admin WITH ENCRYPTED PASSWORD 'STRONG_DB_PASSWORD';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE bhai_production TO bhai_admin;"
sudo -u postgres psql -d bhai_production -c "CREATE EXTENSION IF NOT EXISTS postgis;"
sudo -u postgres psql -d bhai_production -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"

# Apply initial schema tables
psql -h localhost -U bhai_admin -d bhai_production -f database/schema.sql
```

### 3. Python Virtual Environment & Application Setup
```bash
cd /opt/bhai/backend
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

### 4. Create Systemd Service (`/etc/systemd/system/bhai-api.service`)
```ini
[Unit]
Description=BHAI Emergency Response Backend API
After=network.target postgresql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/bhai/backend
EnvironmentFile=/opt/bhai/.env
ExecStart=/opt/bhai/backend/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 4 --proxy-headers
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now bhai-api
sudo systemctl status bhai-api
```

### 5. Nginx TLS & WebSocket Reverse Proxy Configuration (`/etc/nginx/sites-available/bhai.conf`)
```nginx
server {
    listen 80;
    server_name api.bhai.org app.bhai.org;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.bhai.org app.bhai.org;

    ssl_certificate /etc/letsencrypt/live/api.bhai.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.bhai.org/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Security Headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # REST API & Static Files
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSockets (WSS) Live Telemetry Stream
    location /ws/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/bhai.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d api.bhai.org
```

---

## ☁️ Deployment Option 3: Render Cloud Platform

1. **Deploy Managed PostgreSQL with PostGIS:**
   - Create a new PostgreSQL instance on Render.
   - Run `CREATE EXTENSION postgis;` in the Render database console.
2. **Deploy Web Service:**
   - Connect the GitHub repository `mahaveer19s/Bhai-App`.
   - **Root Directory:** `backend`
   - **Environment:** `Python 3`
   - **Build Command:** `pip install -r requirements.txt`
   - **Start Command:** `uvicorn app.main:app --host 0.0.0.0 --port $PORT --proxy-headers`
   - **Health Check Path:** `/health`
3. **Set Environment Variables:**
   - Populate `DATABASE_URL`, `JWT_SECRET`, `OTP_HMAC_SECRET`, `ADMIN_PASSWORD`, `ENVIRONMENT=production`.

---

## 🔍 Verification & Health Checks

Verify operational status immediately following deployment:

| Endpoint | Method | Expected Status | Purpose |
| :--- | :--- | :--- | :--- |
| `/health` | `GET` | `200 OK` (`{"status": "ok"}`) | Load balancer liveness probe |
| `/ready` | `GET` | `200 OK` (`{"database": "connected"}`) | Database connectivity probe |
| `/api/version` | `GET` | `200 OK` | Version metadata check |
| `/admin` | `GET` | `200 OK` | Admin Panel UI access |
| `/docs` | `GET` | `200 OK` | OpenAPI specification |

---

## 🔄 Backup & Rollback Strategy

### 1. Database Backups
```bash
# Automated daily PostgreSQL backup
pg_dump -U bhai_admin -h localhost bhai_production | gzip > /opt/backups/bhai_db_$(date +\%Y\%m\%d).sql.gz
```

### 2. Zero-Downtime Rollback
If a deployment fails validation:
```bash
git checkout <previous-stable-tag>
sudo systemctl restart bhai-api
```
