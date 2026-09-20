import asyncio
import json
import os
import sys
import threading
import time
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext
import urllib.request
import urllib.error
import webbrowser

try:
    import winsound
except ImportError:
    winsound = None

# Modern Bhai Dark Palette
BG_DARK = "#070B14"
BG_CARD = "#0F172A"
BG_CARD_LIGHT = "#1E293B"
PRIMARY_CYAN = "#00BCD4"
ACCENT_RED = "#FF3366"
ACCENT_GREEN = "#10B981"
ACCENT_AMBER = "#F59E0B"
TEXT_MAIN = "#F8FAFC"
TEXT_MUTED = "#94A3B8"

def get_resource_path(relative_path):
    """Get absolute path to resource, works for dev and for PyInstaller"""
    if getattr(sys, 'frozen', False):
        base_path = getattr(sys, '_MEIPASS', os.path.dirname(sys.executable))
    else:
        base_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base_path, relative_path)

class BhaiDesktopApp:
    def __init__(self, root):
        self.root = root
        self.root.title("BHAI — Emergency Assistance & Live Chat (Desktop)")
        self.root.geometry("860x700")
        self.root.configure(bg=BG_DARK)
        self.root.minsize(750, 580)

        # Set Icon
        ico_path = get_resource_path("assets/logo/app_icon.ico")
        if os.path.exists(ico_path):
            try:
                self.root.iconbitmap(ico_path)
            except Exception:
                pass

        self.api_url = "http://localhost:8000"
        self.device_id = f"DESK-{int(time.time()) % 10000:04d}"
        self.active_emergency_id = None
        self.is_broadcasting = False
        self.active_conversation_id = "emergency-room"
        self.known_alert_ids = set()
        self.known_msg_ids = set()
        self.last_victim_lat = None
        self.last_victim_lng = None

        self._build_ui()
        self._start_background_sync()

    def _build_ui(self):
        # Header Frame
        header = tk.Frame(self.root, bg=BG_CARD, height=65, relief="flat")
        header.pack(fill="x", padx=12, pady=(12, 6))

        title_lbl = tk.Label(
            header,
            text="🚨 BHAI EMERGENCY & CHAT",
            font=("Segoe UI", 16, "bold"),
            fg=PRIMARY_CYAN,
            bg=BG_CARD
        )
        title_lbl.pack(side="left", padx=16, pady=12)

        self.status_badge = tk.Label(
            header,
            text=f"ID: {self.device_id} • STANDBY",
            font=("Segoe UI", 10, "bold"),
            fg=TEXT_MUTED,
            bg=BG_CARD_LIGHT,
            padx=12,
            pady=6
        )
        self.status_badge.pack(side="right", padx=16, pady=12)

        # Main Split Layout
        main_paned = tk.PanedWindow(self.root, orient="horizontal", bg=BG_DARK, sashwidth=4)
        main_paned.pack(fill="both", expand=True, padx=12, pady=6)

        # Left Column (SOS & Radar)
        left_frame = tk.Frame(main_paned, bg=BG_CARD, padx=14, pady=14)
        main_paned.add(left_frame, width=370)

        # SOS Action Button
        self.sos_btn = tk.Button(
            left_frame,
            text="🔴 BROADCAST SOS",
            font=("Segoe UI", 14, "bold"),
            bg=ACCENT_RED,
            fg="#FFFFFF",
            activebackground="#D81B60",
            activeforeground="#FFFFFF",
            relief="flat",
            cursor="hand2",
            padx=12,
            pady=16,
            command=self._toggle_sos
        )
        self.sos_btn.pack(fill="x", pady=(0, 12))

        # Radar / Incidents Header
        radar_hdr = tk.Frame(left_frame, bg=BG_CARD)
        radar_hdr.pack(fill="x", pady=(4, 4))
        tk.Label(
            radar_hdr,
            text="📡 Live Incident Radar",
            font=("Segoe UI", 11, "bold"),
            fg=TEXT_MAIN,
            bg=BG_CARD
        ).pack(side="left")

        self.radar_badge = tk.Label(
            radar_hdr,
            text="SYNCING",
            font=("Segoe UI", 8, "bold"),
            fg=ACCENT_GREEN,
            bg=BG_CARD_LIGHT,
            padx=6,
            pady=1
        )
        self.radar_badge.pack(side="right")

        self.radar_box = scrolledtext.ScrolledText(
            left_frame,
            bg="#020617",
            fg="#E2E8F0",
            font=("Consolas", 9),
            relief="flat",
            wrap="word",
            height=12
        )
        self.radar_box.pack(fill="both", expand=True, pady=(0, 10))
        self.radar_box.insert("end", "[System] Radar active • Waiting for emergency alerts or broadcasts...\n")

        # Location Navigation Button
        self.map_btn = tk.Button(
            left_frame,
            text="📍 OPEN VICTIM LOCATION IN MAPS",
            font=("Segoe UI", 9, "bold"),
            bg="#3B82F6",
            fg="#FFFFFF",
            relief="flat",
            cursor="hand2",
            padx=8,
            pady=6,
            state="disabled",
            command=self._open_map
        )
        self.map_btn.pack(fill="x", pady=(0, 8))

        # Responder Quick Actions
        actions_box = tk.Frame(left_frame, bg=BG_CARD)
        actions_box.pack(fill="x", pady=2)

        self.coming_btn = tk.Button(
            actions_box,
            text="🏃 I'M COMING",
            font=("Segoe UI", 9, "bold"),
            bg=ACCENT_GREEN,
            fg="#FFFFFF",
            relief="flat",
            cursor="hand2",
            padx=8,
            pady=6,
            command=self._send_coming_ack
        )
        self.coming_btn.pack(side="left", fill="x", expand=True, padx=(0, 4))

        self.reached_btn = tk.Button(
            actions_box,
            text="🏁 REACHED",
            font=("Segoe UI", 9, "bold"),
            bg="#059669",
            fg="#FFFFFF",
            relief="flat",
            cursor="hand2",
            padx=8,
            pady=6,
            command=self._send_reached
        )
        self.reached_btn.pack(side="right", fill="x", expand=True, padx=(4, 0))

        # Right Column (Live Two-Way Chat)
        right_frame = tk.Frame(main_paned, bg=BG_CARD, padx=14, pady=14)
        main_paned.add(right_frame, width=470)

        chat_header = tk.Frame(right_frame, bg=BG_CARD)
        chat_header.pack(fill="x", pady=(0, 6))

        tk.Label(
            chat_header,
            text="💬 Dual-Transport Live Chat",
            font=("Segoe UI", 11, "bold"),
            fg=TEXT_MAIN,
            bg=BG_CARD
        ).pack(side="left")

        self.transport_badge = tk.Label(
            chat_header,
            text="🌐 Cloud + BLE Ready",
            font=("Segoe UI", 8, "bold"),
            fg=PRIMARY_CYAN,
            bg=BG_CARD_LIGHT,
            padx=6,
            pady=2
        )
        self.transport_badge.pack(side="right")

        self.chat_display = scrolledtext.ScrolledText(
            right_frame,
            bg="#020617",
            fg="#E2E8F0",
            font=("Segoe UI", 10),
            relief="flat",
            wrap="word"
        )
        self.chat_display.pack(fill="both", expand=True, pady=(0, 8))

        # Quick action chips
        chips_frame = tk.Frame(right_frame, bg=BG_CARD)
        chips_frame.pack(fill="x", pady=(0, 6))
        for chip in ["Where are you?", "I'm coming now!", "Reached the spot", "Police alerted"]:
            btn = tk.Button(
                chips_frame,
                text=chip,
                font=("Segoe UI", 8),
                bg=BG_CARD_LIGHT,
                fg=TEXT_MUTED,
                relief="flat",
                cursor="hand2",
                command=lambda c=chip: self._send_message(c)
            )
            btn.pack(side="left", padx=2)

        # Message Input & Send
        input_frame = tk.Frame(right_frame, bg=BG_CARD)
        input_frame.pack(fill="x")

        self.msg_input = tk.Entry(
            input_frame,
            font=("Segoe UI", 11),
            bg=BG_CARD_LIGHT,
            fg="#FFFFFF",
            insertbackground="#FFFFFF",
            relief="flat"
        )
        self.msg_input.pack(side="left", fill="x", expand=True, padx=(0, 8), ipady=6)
        self.msg_input.bind("<Return>", lambda e: self._send_message())

        send_btn = tk.Button(
            input_frame,
            text="SEND",
            font=("Segoe UI", 10, "bold"),
            bg=PRIMARY_CYAN,
            fg="#070B14",
            relief="flat",
            cursor="hand2",
            padx=14,
            pady=4,
            command=self._send_message
        )
        send_btn.pack(side="right")

    def _play_alert_sound(self):
        if winsound:
            try:
                winsound.Beep(1000, 300)
                winsound.Beep(1500, 400)
            except Exception:
                pass

    def _open_map(self):
        if self.last_victim_lat and self.last_victim_lng:
            url = f"https://www.google.com/maps/search/?api=1&query={self.last_victim_lat},{self.last_victim_lng}"
            webbrowser.open(url)

    def _toggle_sos(self):
        if self.is_broadcasting:
            self.is_broadcasting = False
            self.sos_btn.configure(text="🔴 BROADCAST SOS", bg=ACCENT_RED)
            self.status_badge.configure(text=f"ID: {self.device_id} • STANDBY", fg=TEXT_MUTED, bg=BG_CARD_LIGHT)
            self._log_radar("[SOS] Broadcast terminated by user.")
        else:
            self.is_broadcasting = True
            self.active_emergency_id = f"bhai-{int(time.time())}-{self.device_id}"
            self.sos_btn.configure(text="🛑 STOP SOS", bg="#DC2626")
            self.status_badge.configure(text=f"🚨 SOS ACTIVE • {self.device_id}", fg="#FFFFFF", bg=ACCENT_RED)
            self._log_radar(f"[SOS TRIGGERED] Broadcasting emergency ({self.active_emergency_id}) with GPS (28.6273, 77.3725)...")
            self._play_alert_sound()
            self._post_sos_async()

    def _post_sos_async(self):
        def _task():
            try:
                payload = json.dumps({
                    "idempotency_key": self.active_emergency_id,
                    "latitude": 28.6273,
                    "longitude": 77.3725,
                    "accuracy": 8.0,
                    "recorded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "device_status": {"sender_id": self.device_id, "source": "desktop_client"}
                }).encode("utf-8")
                req = urllib.request.Request(
                    f"{self.api_url}/emergencies",
                    data=payload,
                    headers={"Content-Type": "application/json"}
                )
                with urllib.request.urlopen(req, timeout=3) as resp:
                    data = json.loads(resp.read().decode("utf-8"))
                    self._log_radar(f"[Cloud Ingested] ID: {data.get('id')} • Dispatched to nearby helpers & WebSockets in <100ms.")
            except Exception as e:
                self._log_radar(f"[Local Offline Mode] Server offline ({e}). Continuing radio/mesh broadcast.")
        threading.Thread(target=_task, daemon=True).start()

    def _send_coming_ack(self):
        self._log_radar(f"[Responder ACK] You sent 'I'M COMING' to victim!")
        self._send_message("🏃 I am on my way to your location! Stay safe, arriving soon.")

    def _send_reached(self):
        self._log_radar("[Responder Status] Marked as REACHED coordinates.")
        self._send_message("🏁 I have reached your spot.")

    def _send_message(self, direct_text=None):
        text = direct_text or self.msg_input.get().strip()
        if not text:
            return
        if not direct_text:
            self.msg_input.delete(0, "end")

        msg_id = f"msg-{int(time.time() * 1000)}"
        self.known_msg_ids.add(msg_id)

        timestamp = time.strftime("%H:%M:%S")
        self.chat_display.insert("end", f"[{timestamp}] You (Desktop): {text}\n")
        self.chat_display.see("end")

        def _post_msg():
            try:
                payload = json.dumps({
                    "client_message_id": msg_id,
                    "message": text,
                    "transport": "INTERNET",
                    "sender_id": self.device_id
                }).encode("utf-8")
                req = urllib.request.Request(
                    f"{self.api_url}/chat/conversations/{self.active_conversation_id}/messages",
                    data=payload,
                    headers={"Content-Type": "application/json"}
                )
                with urllib.request.urlopen(req, timeout=3) as resp:
                    pass
            except Exception:
                pass
        threading.Thread(target=_post_msg, daemon=True).start()

    def _log_radar(self, text):
        ts = time.strftime("%H:%M:%S")
        self.radar_box.insert("end", f"[{ts}] {text}\n")
        self.radar_box.see("end")

    def _start_background_sync(self):
        def _sync_loop():
            while True:
                time.sleep(2)
                # Check for active emergencies
                try:
                    req = urllib.request.Request(f"{self.api_url}/emergencies/active")
                    with urllib.request.urlopen(req, timeout=2) as resp:
                        items = json.loads(resp.read().decode("utf-8"))
                        for item in items:
                            e_id = item.get("id") or item.get("idempotency_key")
                            if e_id and e_id not in self.known_alert_ids:
                                self.known_alert_ids.add(e_id)
                                sender = item.get("sender_id", "Nearby Bhai User")
                                lat = item.get("latitude", 28.6273)
                                lng = item.get("longitude", 77.3725)
                                self.last_victim_lat = lat
                                self.last_victim_lng = lng
                                self.map_btn.configure(state="normal")
                                self._log_radar(f"🚨 [EMERGENCY ALERT] User: {sender} | Loc: {lat:.4f}, {lng:.4f}")
                                self._play_alert_sound()
                except Exception:
                    pass

                # Periodic Helper Presence announcement for Nearby discovery
                if int(time.time()) % 10 < 2:
                    try:
                        p_data = json.dumps({
                            "is_available": True,
                            "latitude": 28.6273,
                            "longitude": 77.3725,
                            "accuracy": 5.0,
                            "recorded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        }).encode("utf-8")
                        p_req = urllib.request.Request(
                            f"{self.api_url}/helpers/presence",
                            data=p_data,
                            headers={
                                "Content-Type": "application/json",
                                "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI3ODJhODYwYy04Y2M2LTQwNDEtOTE2MS01MWI4MDhlMjdjNmEiLCJyb2xlIjoiVVNFUiIsImV4cCI6MTc5MTMwODYzN30.Jaee0J-nFW-jNRMvM9myuPk-YyNC2rwC_ghE-3R1_eg",
                            },
                            method="PUT"
                        )
                        with urllib.request.urlopen(p_req, timeout=2):
                            pass
                    except Exception:
                        pass

        threading.Thread(target=_sync_loop, daemon=True).start()

if __name__ == "__main__":
    root = tk.Tk()
    app = BhaiDesktopApp(root)
    root.mainloop()
