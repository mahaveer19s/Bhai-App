# BHAI Multi-User Concurrency & Race-Condition Defense

This document specifies the technical design guarantees that enable BHAI to support thousands of concurrent users without data leakage, state collision, or request starvation.

---

## 1. Isolation Principles

### 🛡️ Independent Session Model
1. **No Global State:** There is no single global active emergency object, no shared coordinate holder, and no global timer.
2. **Session-Level Keys:**
   - Every emergency alert has a unique UUID `alert_id`.
   - Every live location stream has a unique UUID `session_id`.
   - Every coordinate breadcrumb belongs explicitly to one `(session_id, user_id)` pair.
3. **Multi-User Isolation Example:**
   - User A starts Emergency → `SESSION_A` (Coordinates: `17.52361, 78.32716`)
   - User C starts Emergency → `SESSION_C` (Coordinates: `17.53000, 78.34000`)
   - User B (Helper) sees both `SESSION_A` and `SESSION_C` simultaneously as distinct cards with independent **NAVIGATE** buttons. Neither session overwrites or blocks the other.

---

## 2. Duplicate-Click Protection & Idempotency

### Frontend Debounce
Mobile client emergency triggers disable the activation button for 3 seconds upon touch and generate a local cryptographic UUID idempotency key before dispatch.

### Backend Unique Constraint
The `emergencies` table enforces a database constraint:
```sql
CONSTRAINT uq_emergency_user_idempotency UNIQUE(user_id, idempotency_key)
```
If network retries or rapid duplicate taps occur, the backend intercepts the duplicate key and returns the existing active incident record without spawning duplicate incidents or notification storms.

---

## 3. Independent Community Responders

When multiple nearby helpers press **"I'M COMING"** simultaneously:
- Each response is inserted into `emergency_responses` with a unique composite key `(emergency_id, helper_user_id)`.
- Responders never overwrite one another.
- The authoritative responder count is computed via `SELECT COUNT(*) FROM emergency_responses WHERE emergency_id = ...`.
- User A and Admin receive live increment notifications (`Responders: 1`, `Responders: 2`).

---

## 4. Automated Concurrency Test Evidence

Validated in [`backend/tests/test_concurrency.py`](file:///d:/DreamProject/bhaiProject/backend/tests/test_concurrency.py):
- 10+ concurrent simulated users trigger emergencies and stream coordinates simultaneously.
- 100% test pass rate with zero collisions or race conditions.
