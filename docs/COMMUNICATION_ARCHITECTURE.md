# BHAI App — Communication Architecture Specification

## Overview

The Bhai Application provides an ultra-fast, resilient, multi-transport safety and emergency dispatch network designed to operate across both online (Internet / WebSockets) and offline (Bluetooth Low Energy radio mesh) conditions.

---

## High-Level Architecture

```
                               ┌───────────────────────────┐
                               │     USER PRESSES SOS      │
                               └─────────────┬─────────────┘
                                             │
                               IMMEDIATE FAST PATH (<50ms)
                        ┌────────────────────┴────────────────────┐
                        ▼                                         ▼
              🚨 LOCAL STATE: ACTIVE                     START AUDIO SIREN
              • Local UUID generated                     • Android Alarm Stream
              • State machine = ACTIVE                   • High-priority notification
              • Haptic feedback                          • Non-blocking UI update
                        │
         ┌──────────────┴──────────────────────────────────────────┐
         │              PARALLEL ASYNCHRONOUS TRANSPORTS           │
         ▼                                                         ▼
┌──────────────────┐                                     ┌──────────────────┐
│  INTERNET PATH   │                                     │  BLUETOOTH PATH  │
│  (Cloud/Backend) │                                     │  (Direct BLE)    │
└────────┬─────────┘                                     └────────┬─────────┘
         │                                                        │
         ▼                                                        ▼
• POST /emergencies (Fast)                               • BLE Advertisement: Type 0x02
• Ingested into Event Bus                                • Legacy 31-byte packet
• Realtime WS to nearby helpers                          • Ephemeral Device IDs
• Central Admin live alert                               • Peer scanning & ACK reception
         │                                                        │
         └──────────────────────────┬─────────────────────────────┘
                                    │
                                    ▼
                         NEARBY BHAI USER DISCOVERY
                                    │
                                    ▼
                          RESPONDER WORKFLOW
                 ├── [ 💬 CHAT ] (Internet or BLE Direct)
                 ├── [ 📍 NAVIGATE ] (Google Maps Directions)
                 ├── [ 🏃 I'M COMING ] (ACK Broadcast)
                 └── [ 🏁 REACHED ] (Status confirmation)
```

---

## Parallel Execution Model

The SOS activation pipeline executes in parallel without synchronous blocking dependencies:

1. **Immediate Local Path (<50ms)**:
   - Sets emergency state to active locally.
   - Activates the continuous siren and Android foreground notification.
   - Dispatches background asynchronous tasks.
2. **GPS Pipeline**:
   - Acquires current GPS coordinates asynchronously without delaying UI responsiveness.
   - Streams live 5-second updates to backend and radio beacons.
3. **Bluetooth Radio Pipeline**:
   - Transmits `0x02` (Emergency SOS) advertisement packet with manufacturer ID `0xFFFF` and magic header `BHAI`.
   - Listens on `EventChannel` for helper acknowledgments (`0x03`).
4. **Internet Pipeline**:
   - Sends non-blocking POST request to `/emergencies` with `client_event_id` idempotency key.
   - Ingests into asynchronous Event Bus.
   - Pushes alert to connected online helpers within the target radius.

---

## Graceful Degradation Matrix

| Network Condition | SOS Broadcast | Nearby Discovery | Chat Channel | Navigation |
|---|---|---|---|---|
| **Internet + Bluetooth ON** | Dual (Cloud + BLE) | Dual (GPS query + BLE scan) | Internet (primary) | Google Maps Turn-by-Turn |
| **Internet Only** | Cloud Realtime | GPS Backend Query | Internet WebSockets | Google Maps Turn-by-Turn |
| **Bluetooth Only (Offline)** | BLE Radio Beacon | BLE Scan | BLE Direct Mesh Chat | Relative Proximity / Last GPS |
| **No Connectivity** | Local Siren + Alert | Offline Storage | Offline Queue (`PENDING`) | Last Cached Coordinates |
