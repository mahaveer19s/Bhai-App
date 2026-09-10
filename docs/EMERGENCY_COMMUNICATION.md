# BHAI Emergency Communication & Responder Lifecycle

## 1. End-to-End Emergency Lifecycle

```
[Victim SOS Press] 
       ↓ 
[Pulsing Siren Starts + GPS Fix] 
       ↓
[BLE SOS Broadcast + Cloud Alert Streamed (5s Interval)]
       ↓
[Nearby Responders Discovered]
       ↓
[Responder Taps "I'M COMING"]
       ↓
[Status = COMING → Turns-by-Turn Navigation via Google Maps]
       ↓
[Real-time Victim ↔ Helper Chat Active]
       ↓
[Responder Arrives & Taps "REACHED"]
       ↓
[Status = REACHED → reached_at Timestamp Recorded]
       ↓
[Victim or Admin Resolves Incident]
       ↓
[Siren Stops → Status = RESOLVED → Chat Becomes Read-Only Archive]
```

---

## 2. Real Responder State Transitions

| State | Trigger | Action Taken |
| :--- | :--- | :--- |
| `CREATED` | Victim triggers SOS button | Offline queue created, siren audio initiated. |
| `ACTIVE` | GPS fix acquired & broadcast | BLE Type 2 sent, Cloud incident created. |
| `COMING` | Helper taps *"I'm Going to Help"* | BLE ACK sent, status updated on server, navigation launched. |
| `REACHED` | Helper taps *"I Have Reached"* | `reached_at` recorded, victim alerted of arrival. |
| `RESOLVED` | Victim or Admin resolves emergency | Siren halts, BLE advertising stops, incident archived. |
