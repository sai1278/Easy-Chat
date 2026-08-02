import json
import time
import urllib.request
import urllib.parse
import urllib.error

BASE_URL = "http://localhost:28080"

def make_request(method, path, headers=None, data=None):
    url = f"{BASE_URL}{path}"
    req_headers = {"Content-Type": "application/json"}
    if headers:
        req_headers.update(headers)
    
    encoded_data = json.dumps(data).encode("utf-8") if data else None
    req = urllib.request.Request(url, data=encoded_data, headers=req_headers, method=method)
    
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode("utf-8")
            return resp.status, json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8")
        try:
            parsed = json.loads(body)
        except Exception:
            parsed = {"error": body}
        return e.code, parsed

def run_tests():
    print("--- 1. AUTHENTICATION FLOWS ---")
    ts = int(time.time())
    device_id = f"dev_{ts}"
    password = "Password123!"
    
    # Register / Onboard
    status, res = make_request("POST", "/api/v1/auth/register", data={"device_id": device_id, "password": password})
    print(f"Register (Onboard): {status} -> {res}")
    
    # Invalid Credentials
    status, res = make_request("POST", "/api/v1/auth/login", data={"device_id": device_id, "password": "WrongPassword"})
    print(f"Invalid Login: {status} -> {res}")
    
    # Valid Login
    status, res = make_request("POST", "/api/v1/auth/login", data={"device_id": device_id, "password": password})
    print(f"Valid Login: {status} -> {res}")
    
    access_token = res.get("access_token")
    headers = {"Authorization": f"Bearer {access_token}"} if access_token else {}
    
    print("\n--- 2. USER PROFILE FLOWS ---")
    status, res = make_request("GET", "/api/v1/user/profile", headers=headers)
    print(f"Get Profile: {status} -> {res}")
    
    status, res = make_request("PUT", "/api/v1/user/profile", headers=headers, data={"display_name": "Test User Updated", "bio": "Hello World"})
    print(f"Update Profile: {status} -> {res}")
    
    print("\n--- 3. NEARBY DISCOVERY FLOWS ---")
    status, res = make_request("POST", "/api/v1/nearby/location", headers=headers, data={"latitude": 37.7749, "longitude": -122.4194})
    print(f"Update Location: {status} -> {res}")
    
    status, res = make_request("GET", "/api/v1/nearby/devices?radius=1000", headers=headers)
    print(f"Get Nearby Devices: {status} -> {res}")
    
    print("\n--- 4. CHAT ROOM & MESSAGING FLOWS ---")
    status, res = make_request("POST", "/api/v1/chat/rooms", headers=headers, data={"name": "General Chat", "type": "public"})
    print(f"Create Room: {status} -> {res}")
    
    room_id = res.get("room_id") or res.get("id") or "default-room"
    
    status, res = make_request("POST", f"/api/v1/chat/rooms/{room_id}/messages", headers=headers, data={"content": "Hello from functional test!"})
    print(f"Send Message: {status} -> {res}")
    
    status, res = make_request("GET", f"/api/v1/chat/rooms/{room_id}/messages", headers=headers)
    print(f"Get Messages: {status} -> {res}")

if __name__ == "__main__":
    run_tests()
