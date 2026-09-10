# BHAI Security, Privacy & Integrity Specification

## 1. Zero Personal Identifiers in BLE Radio Broadcasts
- Bluetooth advertisements strictly use ephemeral 4-byte identifiers derived dynamically.
- Personal data (names, phone numbers, contact lists) is never transmitted over unencrypted radio broadcasts.

---

## 2. Cryptographic Storage & Transport
- **Local Storage**: Encrypted using AES-256-CBC via Flutter Secure Storage and Hive encrypted boxes.
- **In-Transit**: TLS 1.3 / HTTPS for API traffic; JWT with SHA-256 for authenticated requests.
- **Role-Based Access Control (RBAC)**: Strict role enforcement prevents regular users from viewing admin feeds or foreign conversations.

---

## 3. Incident Audit Logging
Every emergency creation, helper response, location update, and cancellation is immutably recorded in `emergency_audit_logs` with actor ID, timestamp, and context metadata.
