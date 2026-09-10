"""
BHAI Emergency Platform — Locust Load Testing Scenario
Supports synthetic stress loads: 1,000 to 100,000 simulated users.

Usage:
  locust -f tests/load/locustfile.py --host=http://localhost:8000
"""

import random
import uuid
from locust import HttpUser, task, between

class BhaiAppSimulatedUser(HttpUser):
    wait_time = between(4.5, 5.5)  # Simulates 5-second location heartbeat

    def on_start(self):
        """Authenticate user and obtain JWT token."""
        self.phone = f"+9198{random.randint(10000000, 99999999)}"
        self.session_id = None
        self.headers = {"Content-Type": "application/json"}
        
        # In dev mode, verify with DEV_OTP_CODE
        auth_resp = self.client.post("/auth/verify-otp", json={
            "phone": self.phone,
            "code": "000000"
        })
        if auth_resp.status_code == 200:
            token = auth_resp.json().get("access_token")
            self.headers["Authorization"] = f"Bearer {token}"

    @task(10)
    def stream_live_location(self):
        """Simulate 5-second asynchronous live GPS coordinate streaming."""
        if not self.headers.get("Authorization"):
            return

        # Start session if not already active
        if not self.session_id:
            lat = 17.3850 + (random.random() - 0.5) * 0.05
            lng = 78.4867 + (random.random() - 0.5) * 0.05
            resp = self.client.post("/live-location/start", json={
                "latitude": lat,
                "longitude": lng,
                "accuracy": 7.5
            }, headers=self.headers)
            if resp.status_code == 200:
                self.session_id = resp.json().get("session_id")
        else:
            # Send 5-second coordinate breadcrumb
            lat = 17.3850 + (random.random() - 0.5) * 0.05
            lng = 78.4867 + (random.random() - 0.5) * 0.05
            self.client.post("/live-location/update", json={
                "session_id": self.session_id,
                "latitude": lat,
                "longitude": lng,
                "accuracy": 5.0
            }, headers=self.headers)

    @task(1)
    def trigger_emergency_flow(self):
        """Simulate occasional emergency trigger (1 in 10 tasks)."""
        if not self.headers.get("Authorization"):
            return

        lat = 17.3850 + (random.random() - 0.5) * 0.05
        lng = 78.4867 + (random.random() - 0.5) * 0.05
        idempotency_key = str(uuid.uuid4())
        
        self.client.post("/emergencies/trigger", json={
            "latitude": lat,
            "longitude": lng,
            "accuracy": 6.0,
            "idempotency_key": idempotency_key
        }, headers=self.headers)
