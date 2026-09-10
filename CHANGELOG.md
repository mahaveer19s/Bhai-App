# Changelog

All notable changes to the BHAI emergency assistance platform are documented here.

---

## [1.2.0] — 2026-09-10

### Added
- **5-Second Asynchronous Live Location Streaming:** Independent session model (`/live-location/start`, `/live-location/update`, `/live-location/stop`).
- **User A → User B Direct Navigation:** Dynamic Google Maps directions link generated from real-time coordinates.
- **Community Responder Acknowledgement:** Independent `"I'M COMING"` responses with real-time incrementing helper counts.
- **Admin Command Center:** Real-time metrics, OpenStreetMap live telemetry radar, and incident resolution controls.
- **Strict GPS Coordinate Sanitization:** Automatic rejection of Null Island `(0,0)`, `NaN`, and boundary violations.
- **Multi-Device Concurrency Test Suite:** Validated 10+ concurrent users with zero state collision.
- **Load Testing Framework:** Locust and k6 synthetic load scripts supporting up to 100k simulated users.

### Changed
- Refactored emergency lifecycle state machine (`CREATED` → `ACTIVE` → `ACKNOWLEDGED` → `RESOLVED` / `CANCELLED`).
- Updated Docker configurations and multi-stage container build definitions.
- Enhanced PostGIS GIST spatial indexing for nearby helper queries.

### Fixed
- Fixed web simulator base href issue (`/app/`) resolving white screen display.
- Eliminated all static/mock metrics in admin console in favor of authoritative database queries.

### Security
- Enforced strict Role-Based Access Control (RBAC) on all `/admin/*` routes.
- Privacy-gated exact location coordinates, revealing exact live points only to acknowledged responders.
