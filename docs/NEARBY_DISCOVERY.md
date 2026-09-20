# Bhai Dual-Mode Nearby Discovery & Deduplication

## 1. Discovery Pipelines

Bhai utilizes two distinct discovery mechanisms to detect peers:

### A. Internet / GPS Geospatial Discovery
- Active when cellular data or Wi-Fi is available.
- PostGIS database calculation (`ST_DWithin` & `ST_Distance`) filtering available verified helpers within a configurable radius ($500\text{m}$, $1000\text{m}$, $2000\text{m}$).
- Returns exact geographic distance, availability status, and last seen timestamp.

### B. Bluetooth Low Energy Discovery
- Active in all network conditions (online, offline, flight mode with Bluetooth enabled).
- Continuous background radio scanning for Manufacturer ID `0xFFFF` and magic bytes `"BHAI"`.
- Calculates signal proximity via RSSI:
  - $\ge -60\text{ dBm}$: Immediate ($\approx 1\text{--}5\text{m}$)
  - $\ge -75\text{ dBm}$: Very Near ($\approx 5\text{--}15\text{m}$)
  - $\ge -88\text{ dBm}$: Nearby ($\approx 15\text{--}30\text{m}$)
  - $< -88\text{ dBm}$: In Bluetooth Range ($\approx 30\text{--}50\text{m}$)

---

## 2. Cross-Transport Deduplication

When a nearby peer is detected via both GPS query and BLE advertisement, the frontend deduplication engine merges the records into a single card:
- Displays `🌐 + 📡 Dual` badge.
- Shows exact GPS distance while keeping the active direct BLE channel open.
- Prevents redundant UI duplicate entries.
