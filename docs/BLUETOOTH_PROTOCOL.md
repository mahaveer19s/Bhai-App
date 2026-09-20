# Bhai BLE Protocol Specification

## 1. Frame Structure

All Bhai Bluetooth Low Energy advertisement packets adhere to the legacy 31-byte advertising standard and manufacturer-specific payload data under Manufacturer ID `0xFFFF`.

### 23–27 Byte Binary Packet Layout

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|       'B'     |       'H'     |       'A'     |       'I'     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|      Type     |             Sender Ephemeral ID (4B)          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|   Sender ID   |             Target Ephemeral ID (4B)          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|   Target ID   |                  Payload Data                 |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                      ... (Payload continues)                  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|    Checksum   |
+-+-+-+-+-+-+-+-+
```

---

## 2. Packet Types

| Type Code | Name | Description | Payload Content |
|---|---|---|---|
| `0x01` | **Presence Beacon** | Standby peer detection | Nonce / Status flags |
| `0x02` | **Emergency SOS Alert** | Active emergency broadcast | Encoded Lat/Lon + Location Flag |
| `0x03` | **Alert ACK** | Helper acknowledgment ("I'M COMING") | Nonce |
| `0x04` | **Direct BLE Chat** | Chunked text message transmission | Message ID (2B) + Chunk Info (1B) + UTF-8 Text (10B) |

---

## 3. Privacy-Preserving Ephemeral IDs

- Device IDs are truncated cryptographic hashes (`SHA-256(device_seed)[0:8]`).
- Raw telephone numbers, user names, and exact street addresses are **never** included inside BLE broadcast packets.
- Hardware scanning filters for `"BHAI"` magic bytes (`0x42 0x48 0x41 0x49`) to ignore non-Bhai devices such as headphones, smart watches, and laptops.
