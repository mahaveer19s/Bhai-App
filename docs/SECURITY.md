# BHAI Security Architecture & Privacy Safeguards

This document defines the security architecture, authorization controls, and privacy boundaries protecting sensitive user identities and real-time location data.

---

## 1. Authentication & Role-Based Access Control (RBAC)

### Token-Based Authentication
- Client requests authenticate via cryptographic HMAC/RSA signed JSON Web Tokens (`Bearer <TOKEN>`).
- Tokens encode `user_id`, `role` (`USER` or `ADMIN`), and expiration timestamp `exp`.

### Admin Privilege Isolation
- Admin endpoints under `/admin/*` and the `/ws/admin` WebSocket strictly enforce `role == "ADMIN"`.
- Requests from normal `USER` accounts attempting to invoke admin routes receive an immediate `403 Forbidden` response.

---

## 2. Real-Time Location Privacy & IDOR Prevention

### Exact vs Approximate Location Gating
- **Public / Unauthenticated:** Coordinates are never exposed publicly.
- **Nearby Helpers:** When an emergency is triggered, nearby helpers receive distance estimates and direction vectors. Exact live location coordinate breadcrumbs are shared with a helper **ONLY AFTER** that helper explicitly acknowledges with `"I'M COMING"` or `"HELPING"`.
- **Session Ownership:** Users can only append location updates to `live_location_sessions` matching their authenticated `user_id`. Attempts to post coordinates to other users' sessions are rejected.

---

## 3. Coordinate & Input Sanitization

- **Null Island Rejection:** Strict backend validators reject `(0.00000, 0.00000)`, `NaN`, `null`, and infinity.
- **Range Constraints:** Latitude is bounded within `[-90, 90]` and Longitude within `[-180, 180]`.
- **Rate Limiting:** `SlowAPI` enforces token-bucket rate limits (e.g., 60 req/min for location updates) to prevent denial-of-service spam while accommodating legitimate 5-second streaming.

---

## 4. Secret & Key Management

- **Zero Secret Exposure:** No database passwords, JWT secrets, Twilio auth tokens, or Firebase private keys are stored in client source code or committed to GitHub.
- **Environment Isolation:** All secret configuration is loaded via environment variables or cloud secret managers (Render Secret Files / Supabase Vault).
