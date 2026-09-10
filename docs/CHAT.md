# BHAI Emergency Chat Architecture & Transport Abstraction

## 1. Overview
The BHAI emergency chat system allows real-time two-way communication between victims, authorized nearby community helpers, and the central emergency operations team.

---

## 2. Unified Transport Architecture

```
                       +-------------------------+
                       |       ChatService       |
                       +-------------------------+
                                    |
                    +---------------+---------------+
                    |                               |
        +-----------------------+       +-----------------------+
        |   InternetTransport   |       |   BluetoothTransport  |
        |  (REST + WebSockets)  |       |  (BLE 2.4 GHz Mesh)   |
        +-----------------------+       +-----------------------+
                    |                               |
        +-----------------------+       +-----------------------+
        |   FastAPI & DB Sync   |       |   Local Peer Radio    |
        +-----------------------+       +-----------------------+
```

### Transport Selector Logic
- **When Internet is Connected**: `InternetTransport` transmits messages with sub-second latency, updates delivery/read timestamps, and broadcasts to authorized WebSocket listeners.
- **When Internet is Unavailable**: `BluetoothTransport` broadcasts messages over 2.4 GHz BLE radio directly to nearby peers within radio range.
- **When Reconnected**: Local offline queue automatically flushes pending messages to the backend using idempotent `client_message_id` keys.

---

## 3. Multi-Conversation Isolation & Security
- Every conversation is keyed by a unique `conversation_id` linked to an active `alert_id`.
- **Authorization Enforcement**: Only the victim, the assigned responder, or an authenticated administrator can access the thread. Cross-conversation data leakage is strictly blocked at the API layer with HTTP 403.

---

## 4. Message Lifecycle States
1. `SENDING`: Message dispatched locally to transport.
2. `SENT`: Acknowledged by cloud server or local BLE transmitter.
3. `DELIVERED`: Received by target recipient device.
4. `READ`: Viewed on recipient screen.
5. `WAITING FOR CONNECTION`: Queued in local persistent storage awaiting network/peer availability.
