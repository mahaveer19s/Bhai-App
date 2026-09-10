# BHAI Verification & Automated Test Suite

## 1. Test Architecture
The test suite validates:
1. **Admin RBAC Security**: Unauthenticated and normal user access rejection.
2. **Authentication**: OTP life-cycle, JWT expiration, token revocation.
3. **Emergency API**: Validation schemas, duplicate prevention, cancellation reasons.
4. **Responder Flows**: `ACKNOWLEDGED` $\rightarrow$ `COMING` $\rightarrow$ `REACHED` $\rightarrow$ `RESOLVED`.
5. **Chat Lifecycle**: Multi-conversation isolation, deduplication, delivery receipts.
6. **Concurrency**: Independent live location streams and high-concurrency alert creation.
7. **Geospatial Discovery**: PostGIS/Haversine radius queries.

---

## 2. Running Automated Tests
```powershell
# Run all backend pytest tests
cd backend
& .venv\Scripts\python.exe -m pytest -v
```
**Current Status**: **24 / 24 Tests Passing (100%)**.
