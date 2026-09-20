# Bhai Concurrency & Idempotency Architecture

## 1. Client Idempotency

Every emergency activation and chat message generates a client-side unique identifier:
- Emergency: `client_event_id` (UUID format).
- Chat: `client_message_id` (`msg-{timestamp}-{deviceId}`).

If the same operation is transmitted across dual transports (e.g. Internet and Bluetooth concurrently) or retried following connectivity restoration, the backend safely deduplicates the request and returns the existing resource without creating duplicate incident rows.

---

## 2. Asynchronous Queue Processing

- SQLite store-and-forward queue in Flutter client for operations created while offline.
- Backend `AsyncEventBus` with non-blocking workers preventing slow third-party services (FCM push, SMS gateway) from blocking HTTP responses.
- Independent, thread-safe live-location streams per active session.
