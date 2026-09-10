# BHAI Bluetooth Low Energy (BLE) Protocol Specification (V1)

## 1. Overview
The **BHAI Bluetooth Protocol** provides high-speed, 100% offline, peer-to-peer discovery and store-and-forward message transmission across nearby mobile devices operating in crisis zones where cellular towers or Wi-Fi infrastructure have failed.

---

## 2. Packet Architecture & 31-Byte Legacy Limits
To ensure universal hardware compatibility across all Android and iOS chipsets without requiring extended advertising packets, the Bhai discovery frame fits within standard 31-byte legacy BLE advertisement limits.

### Manufacturer Specific Data Structure (ID: `0xFFFF`)

```
+-------------------------------------------------------------------------------+
| Byte Offset | Field Length | Data Type | Description                          |
+-------------------------------------------------------------------------------+
| 0 - 3       | 4 bytes      | ASCII     | Magic Header: "BHAI" (0x42,0x48,0x41,0x49) |
| 4           | 1 byte       | uint8     | Packet Type: 0x01..0x04              |
| 5 - 8       | 4 bytes      | Hex/Bytes | Sender Ephemeral Device ID           |
| 9 - 12      | 4 bytes      | Hex/Bytes | Target Ephemeral Device ID           |
| 13 - 16     | 4 bytes      | int32     | Packed Latitude (lat * 100,000)      |
| 17 - 20     | 4 bytes      | int32     | Packed Longitude (lon * 100,000)     |
| 21          | 1 byte       | uint8     | Location Valid Flag (1=Valid, 0=None)|
| 22          | 1 byte       | uint8     | Rolling Sequence / Nonce (Anti-replay)|
+-------------------------------------------------------------------------------+
Total Payload Length: 23 Bytes (Remaining 8 bytes reserved for BLE flags/headers)
```

---

## 3. Packet Types

| Type Code | Name | Function |
| :--- | :--- | :--- |
| `0x01` | **Presence Beacon** | Periodic background heartbeat beacon so nearby helpers can discover available peers. Target ID is `00000000`. |
| `0x02` | **Emergency Distress Alert (SOS)** | High-priority emergency broadcast sent upon SOS activation. Contains packed GPS coordinates. Target ID is `00000000` (broadcast) or specific helper. |
| `0x03` | **Alert Acknowledgment (ACK)** | Direct confirmation sent by a helper device to the victim's device confirming *"I'm going to help"*. Target ID matches victim's ephemeral ID. |
| `0x04` | **Direct Chat / Safety Status** | Direct peer-to-peer message chunk or safety status code (`"REACHED"`, `"SAFE"`, `"GATE"`). |

---

## 4. Ephemeral Identity & Privacy
- **No Personal Information Broadcast**: Advertisements strictly exclude names, phone numbers, or email addresses.
- **Ephemeral Identifier**: Each device computes a 4-byte truncated cryptographic hash from local secure entropy.
- **Self-Filtering**: Hardware scanner filters discard packets originating from the device's own local ephemeral ID to prevent feedback loops.

---

## 5. Laptop & Desktop Compatibility
- A desktop or laptop with Bluetooth turned on is **NOT** recognized as a Bhai user unless it is executing the official Bhai BLE specification with manufacturer ID `0xFFFF` and magic bytes `BHAI`.
- Windows BLE testing requires Bluetooth 4.2+ Low Energy adapter with peripheral advertising support enabled.
