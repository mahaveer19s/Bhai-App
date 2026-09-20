# Privacy & Data Governance Architecture — BHAI

This document provides a transparent, comprehensive disclosure of how data is processed, stored, and protected within the **BHAI Emergency Assistance Platform**.

---

## 🔒 Privacy-by-Design Principles

1. **Zero Commercial Monetization:** BHAI contains no third-party advertising SDKs, behavioral tracking pixels, or data-brokering integrations.
2. **Minimal Data Collection:** The platform requests and processes only the minimum necessary telemetry required to dispatch assistance during an active emergency.
3. **Protective Location Shielding:** Exact GPS coordinates of a victim in distress are obfuscated from community helpers until a helper explicitly commits to assist.
4. **Airwave Sanitization:** Bluetooth Low Energy (BLE) advertisements broadcasted during offline emergencies contain no names, phone numbers, IP addresses, or permanent device serials.

---

## 📊 Processed Data Categories & Access Matrix

| Data Category | Specific Elements | Operational Purpose | Access Authorization | Retention Policy |
| :--- | :--- | :--- | :--- | :--- |
| **Account Information** | Phone number, display name | User authentication & SMS alerts | Protected user, Admin | Active account lifetime |
| **GNSS / GPS Coordinates** | Latitude, Longitude, Altitude, Accuracy, Timestamp | Turn-by-turn navigation & spatial dispatch | Protected user, Accepted Responders, Admin | Configurable (Default: 90 days, purged via scheduled task) |
| **Network Audit Metadata** | Server-observed IP, Port, Protocol Version | Forensic auditing, DDoS protection, fraud detection | **Admin Operators Only (`AUDIT_VIEW_IP`)** | Retained with incident audit log |
| **Emergency Chat** | Message text, client timestamp, delivery status | Operational coordination during distress | Incident participants (Victim, Responders, Admin) | Linked to emergency record |
| **BLE Distress Beacons** | Ephemeral ID (`EPH-XXXXXX`), Hop Count, RSSI | Offline proximity discovery when cellular is unavailable | Public radio airwaves (Truncated hash only) | Transient (In-memory, expires after 5 minutes) |
| **Responder Telemetry** | Response status (`COMING`, `REACHED`), distance | Real-time helper coordination for victim screen | Victim (Count & Distance only), Admin | Linked to emergency record |

---

## 🚫 What We Do NOT Collect or Transmit

- ❌ **No Continuous Background Location Harvesting:** The application requests location only when an SOS is actively triggered or when a user opts in as an active community volunteer helper.
- ❌ **No Device Identifier Fingerprinting:** Does not harvest IMEI, MAC addresses, or SIM card serial numbers.
- ❌ **No Address Book Scraping:** Does not upload the user's complete contact directory; only specific trusted emergency contacts explicitly selected by the user are stored.
- ❌ **No IP Leakage over BLE:** IP addresses are never transmitted over Bluetooth Low Energy airwaves.

---

## 🛰️ Physical Location vs. Network IP Address

The platform makes a strict distinction between **physical location** and **network audit data**:
- **Physical Position:** Sourced exclusively from the device's hardware GNSS/GPS constellation and satellite telemetry.
- **IP Address:** Network layer metadata observed by the server. An IP address is **not** treated as a reliable proxy for physical location and is never used to compute helper-to-victim distance.

---

## 🔄 Data Retention & Automated Purging

- **Location Breadcrumb History:** The backend includes an automated retention service (`app.services.retention.purge_expired_location_history`) that purges GPS coordinates older than `LOCATION_RETENTION_DAYS` (default: 90 days).
- **Incident Cancellation / Resolution:** Once resolved, real-time WebSocket streams and live location timers are terminated immediately.
