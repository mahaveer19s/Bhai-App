# BHAI Scalability & Throughput Architecture

This document describes the architectural scalability parameters, connection models, and throughput boundaries for the BHAI platform.

---

## 1. Workload Projections & Ingestion Rates

| Metric | Target Baseline | High-Load Peak | Extreme Disaster Mode |
| :--- | :--- | :--- | :--- |
| **Registered Users** | 100,000 | 1,000,000 | 5,000,000+ |
| **Concurrent Active Users** | 5,000 | 50,000 | 250,000 |
| **Active Emergencies** | 50 | 500 | 5,000 |
| **Live Location Streams (Active)** | 100 | 2,000 | 20,000 |
| **Location Updates Ingestion (req/s)**| 20 req/s | 400 req/s | 4,000 req/s |

---

## 2. Asynchronous Ingestion & Database Sharding

### 5-Second Live Stream Ingestion
Rather than holding open persistent HTTP streams, each coordinate point is an independent, lightweight `POST /live-location/update` request:
- **Payload Size:** ~120 bytes per JSON update.
- **Latency Target:** p95 < 25ms.
- **Connection Model:** Fast HTTP/2 multiplexing with connection reuse.

### Database Indexing & Retention
- **Spatial Partitioning:** PostGIS GIST indexes on `helper_presence.last_location` allow sub-millisecond radius filtering across 100,000+ registered helpers.
- **Automated Data Purge:** `LOCATION_RETENTION_DAYS` (default: 90 days) prunes old coordinate breadcrumbs from resolved incidents during startup and scheduled background maintenance jobs.

---

## 3. Horizontal Scaling & High Availability

1. **Stateless API Gateway:** FastAPI instances are completely stateless and horizontally scalable behind any reverse proxy or load balancer (Nginx, Traefik, AWS ALB, Render Load Balancer).
2. **WebSocket Pub/Sub Layer:** For single-node deployment, in-memory `RealtimeEmergencyManager` routes events across local tasks. For multi-node cluster scale-out, Redis Pub/Sub or Supabase Realtime adapter broadcasts events across instances.
3. **Database Connection Pooling:** Managed via `asyncpg` connection pool with automatic recycling, statement caching, and bounded concurrency.
