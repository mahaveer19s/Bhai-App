# Bhai Realtime WebSocket & Event Bus Architecture

## 1. Overview

Bhai employs a reactive, non-blocking real-time delivery layer connecting mobile clients, helpers, and administrative command centers.

---

## 2. WebSocket Endpoints

| Endpoint | Protocol | Purpose |
|---|---|---|
| `/ws/user` or `/ws/alerts` | WSS / WS | User-level alert stream for instant incoming emergency notifications and private messages |
| `/ws/emergencies/{emergency_id}` | WSS / WS | Incident-level stream broadcasting live responder statuses, locations, and state changes |
| `/ws/chat/{conversation_id}` | WSS / WS | Private 2-way conversation stream between victim, helper, and admin |
| `/ws/admin` | WSS / WS | Operations command center feed with global incident updates |

---

## 3. Decoupled Asynchronous Event Bus

Backend services publish incident events to an asynchronous event bus (`AsyncEventBus` in `app/services/event_bus.py`) with decoupled topic routing:

- `emergency.created`: Dispatched to nearby helpers and admin.
- `emergency.updated`: Broadcasts state changes.
- `location.updated`: High-frequency (5s) coordinate streams.
- `chat.message`: Direct participant and user delivery.
- `responder.status`: Tracks `COMING` and `REACHED` confirmations.
