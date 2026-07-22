import time
import json
from locust import HttpUser, task, between, events, LoadTestShape
import websocket

class NearbyConnectUser(HttpUser):
    wait_time = between(1, 3)
    token = None
    user_id = None

    def on_start(self):
        """Anonymous Auth Initialization upon VU start"""
        payload = {
            "device_id": f"locust_device_{id(self)}",
            "password": "Password123!"
        }
        with self.client.post("/api/v1/auth/login", json=payload, catch_response=True) as response:
            if response.status_code == 200:
                data = response.json()
                self.token = data.get("access_token")
                self.user_id = f"locust_user_{id(self)}"
                response.success()
            else:
                response.failure(f"Auth failed: {response.status_code}")

    @task(3)
    def presence_heartbeat(self):
        """Presence Heartbeat task"""
        if not self.token:
            return
        headers = {"Authorization": f"Bearer {self.token}"}
        payload = {
            "user_id": self.user_id,
            "state": "online",
            "h3_index": "8a2a1072b59ffff"
        }
        self.client.post("/api/v1/presence/heartbeat", json=payload, headers=headers, name="Presence Heartbeat")

    @task(3)
    def nearby_discovery(self):
        """Nearby H3 Proximity Search task"""
        if not self.token:
            return
        headers = {"Authorization": f"Bearer {self.token}"}
        self.client.get("/api/v1/nearby/discover?h3_index=8a2a1072b59ffff&radius=150", headers=headers, name="Nearby Discovery")

    @task(2)
    def media_upload(self):
        """Media upload task"""
        if not self.token:
            return
        headers = {"Authorization": f"Bearer {self.token}"}
        payload = {
            "filename": f"media_locust_{id(self)}.png",
            "content_type": "image/png",
            "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        }
        self.client.post("/api/v1/media/upload", json=payload, headers=headers, name="Media Upload")

    @task(1)
    def websocket_messaging(self):
        """WebSocket Real-Time Messaging Session"""
        if not self.token:
            return
        
        ws_host = self.host.replace("http://", "ws://").replace("https://", "wss://")
        ws_url = f"{ws_host}/ws?token={self.token}"
        
        start_time = time.time()
        try:
            ws = websocket.create_connection(ws_url, timeout=5)
            payload = json.dumps({
                "type": "MESSAGE",
                "message": {
                    "message_id": f"locust_msg_{id(self)}_{int(time.time())}",
                    "room_id": "00000000-0000-0000-0000-000000000001",
                    "sender_id": self.user_id,
                    "encrypted_payload": "TG9jdXN0IFdlYlNvY2tldCBUZXN0"
                }
            })
            ws.send(payload)
            ws.close()
            total_time = int((time.time() - start_time) * 1000)
            events.request.fire(
                request_type="WebSocket",
                name="WS Messaging",
                response_time=total_time,
                response_length=len(payload),
                exception=None
            )
        except Exception as e:
            total_time = int((time.time() - start_time) * 1000)
            events.request.fire(
                request_type="WebSocket",
                name="WS Messaging",
                response_time=total_time,
                response_length=0,
                exception=e
            )

class StepLoadShape(LoadTestShape):
    """
    Ramp up stages to test 100, 500, 1000, and 5000 concurrent user tiers.
    """
    stages = [
        {"duration": 120, "users": 100, "spawn_rate": 10},
        {"duration": 420, "users": 100, "spawn_rate": 10},
        {"duration": 600, "users": 500, "spawn_rate": 50},
        {"duration": 900, "users": 500, "spawn_rate": 50},
        {"duration": 1200, "users": 1000, "spawn_rate": 100},
        {"duration": 1500, "users": 1000, "spawn_rate": 100},
        {"duration": 1800, "users": 5000, "spawn_rate": 200},
        {"duration": 2400, "users": 5000, "spawn_rate": 200},
    ]

    def tick(self):
        run_time = self.get_run_time()
        for stage in self.stages:
            if run_time < stage["duration"]:
                return (stage["users"], stage["spawn_rate"])
        return None
