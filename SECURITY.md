# Security Architecture & Vulnerability Disclosure Policy — BHAI

This document outlines the security architecture, threat model, trust boundaries, cryptographic controls, and vulnerability reporting procedures implemented in the **BHAI Emergency Assistance Platform**.

---

## 🛡️ Security Architecture & Threat Model

BHAI is engineered for high-concurrency life-safety workflows where confidentiality, integrity, availability, and non-repudiation are vital.

```text
[ UNTRUSTED PEERS / AIRWAVES ]
       │  (BLE 2.4 GHz - Truncated Ephemeral Distant Packets)
       ▼
[ CLIENT APPLICATION (Flutter / Kotlin) ]
       │  (TLS 1.3 / HTTPS / WSS)
       ▼
[ TRUSTED REVERSE PROXY (Nginx / Cloudflare) ]
       │  (Trusted Proxy Header Forwarding)
       ▼
[ FASTAPI BACKEND GATEWAY ]
  ├── JWT Role-Based Authorization
  ├── Rate Limiting & Debounce Engine
  ├── Geodesic Haversine Calculation
  └── Structured Network Audit Logger
       │
       ▼
[ AUTHORITATIVE DATABASE (PostgreSQL + PostGIS) ]
```

---

## 🏛️ Trust Boundaries & Access Controls

### 1. Client Device Boundary
- **Threat:** Physical device inspection, compromised OS, or reverse-engineered client APK.
- **Controls:**
  - Local database encryption using AES-256 for offline queued operations.
  - Ephemeral session keys rotated per incident.
  - No secret API keys or database credentials embedded in the mobile binary.

### 2. Airwave / Bluetooth Transport Boundary
- **Threat:** BLE sniffing, packet spoofing, relay replay attacks.
- **Controls:**
  - Zero sensitive metadata (no phone numbers, passwords, JWTs, or IP addresses) in BLE advertisements.
  - Truncated 16-character SHA-256 hashes for ephemeral device identification (`EPH-XXXXXX`).
  - Packet timestamp validation with automatic hop-count decrement (`max_hops=3`) to prevent infinite relay loops.

### 3. Network Transport Boundary
- **Threat:** Man-In-The-Middle (MITM) attacks, token hijacking, session eavesdropping.
- **Controls:**
  - Strict HTTPS (TLS 1.2 / TLS 1.3) and WSS for all internet communications.
  - Security headers enforced: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Strict-Transport-Security: max-age=31536000`, `Referrer-Policy: strict-origin-when-cross-origin`.

### 4. Application & Database Boundary
- **Threat:** SQL Injection, Insecure Direct Object References (IDOR), unauthorized location harvesting.
- **Controls:**
  - Parameterized ORM queries via SQLAlchemy 2.0.
  - Spatial bounding queries via PostGIS (`ST_DWithin`) scoped to authorized geographic radiuses.
  - Exact victim location is cryptographically hidden until a nearby helper explicitly accepts an incident (`I'M COMING`).

---

## 🔍 Server-Observed IP Audit Model & Proxy Hardening

IP addresses are classified as **Administrative Network Audit Metadata** and are subject to strict access controls:

| Role | Access to Client IP | Justification |
| :--- | :--- | :--- |
| **Normal User / Victim** | `DENIED (403)` | Privacy protection; no operational need |
| **Community Helper** | `DENIED (403)` | Privacy protection; helper navigates by GPS coordinates only |
| **Public API / Unauthenticated** | `DENIED (401/403)` | Prevent network reconnaissance |
| **Admin Operator (`AUDIT_VIEW_IP`)** | `PERMITTED` | Forensic incident audit & law enforcement coordination |

### Trusted Reverse Proxy Extraction Chain
The backend resolves the client IP using a secure two-tier validation algorithm:
1. **Peer Socket Validation:** Verifies if `request.client.host` originates from an IP in `TRUSTED_PROXIES` (e.g., `127.0.0.1`, `10.0.0.0/8`).
2. **Header Evaluation:** Only if the peer is a trusted proxy, parses `X-Forwarded-For` or `X-Real-IP`. Direct requests from untrusted clients cannot spoof arbitrary proxy headers.
3. **RFC 1918 Private IP Classification:** Uses Python's `ipaddress` module to categorize addresses as `PRIVATE` (local subnet/NAT) or `GLOBAL` (public internet).
4. **Offline Guard:** If the device communicates via BLE only or is disconnected, the system explicitly returns `No current server-observed IP available (Offline transport)` and never fabricates dummy coordinates or `0.0.0.0`.

---

## 🔑 Authentication & Session Security

- **OTP Challenges:** Authenticated using HMAC-SHA256 with server-side secrets (`OTP_HMAC_SECRET`). Verified in constant time via `hmac.compare_digest` to eliminate timing side-channel attacks.
- **Access Tokens:** Stateless signed JWTs (`HS256`) containing explicit user IDs and role claims (`USER`, `ADMIN`).
- **Admin Authentication:** Authenticated with constant-time `secrets.compare_digest` verification.

---

## 🚫 IDOR & Chat Isolation Controls

- **Emergency Scoping:** Chat endpoints (`/chat/conversations/{id}/messages`) verify that the requesting user is either the victim, an accepted helper, or an administrator for that specific emergency.
- **Isolation Guarantee:** Changing the `emergency_id` or `conversation_id` in API requests returns `HTTP 403 Forbidden` or `HTTP 404 Not Found`. Users cannot inspect or inject messages into other emergencies.

---

## 🛡️ Vulnerability Disclosure Policy

If you discover a security vulnerability in the Bhai platform, please report it privately:

- **Email:** `security@bhai.org`
- **PGP Key:** Available upon request.
- **Response Timeline:** Acknowledgment within 24 hours; remediation within 7 days for critical findings.

*Please do not open public GitHub issues for security vulnerabilities.*
