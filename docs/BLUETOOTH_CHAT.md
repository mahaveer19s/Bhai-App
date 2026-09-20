# Bhai Bluetooth Direct Mesh Chat Architecture

## 1. Overview

Bhai provides direct device-to-device communication using Bluetooth Low Energy advertising channels when Internet connectivity is unavailable. This allows nearby users to coordinate during emergencies without cellular data or Wi-Fi infrastructure.

---

## 2. Framing & Chunking Protocol

Because legacy BLE advertisement frames have a maximum payload limitation (~31 bytes total, ~10-12 bytes per custom manufacturer slice), text messages are chunked and framed:

```
[Packet Header: 4B "BHAI"] [Type: 0x04] [SenderID: 4B] [TargetID: 4B] [MsgID: 2B] [ChunkInfo: 1B] [Payload: 1-10B] [Checksum: 1B]
```

### ChunkInfo Byte Layout
- **Bits 7–4**: Chunk Index ($0$ to $15$).
- **Bits 3–0**: Total Chunks in message ($1$ to $15$).

### Transmission Pipeline
1. `ChatService.sendMessage()` selects `BluetoothTransport` when offline.
2. Text string is UTF-8 encoded and segmented into 10-byte slices.
3. Native `MainActivity.kt` transmits each chunk as an advertisement burst with a 180ms inter-chunk delay.
4. Receiver scans for `0x04` packets and buffers them by `MsgID`.
5. Upon receiving all slices, the full message is reassembled and pushed directly into `ChatService.ingestIncomingMessage()`.
6. UI displays the `📡 Bluetooth Direct` transport badge and delivery checkmark.
