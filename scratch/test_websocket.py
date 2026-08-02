import asyncio
import json
import urllib.request

BASE_URL = "http://localhost:28080"

def get_auth_token():
    ts = int(time.time())
    device_id = f"dev_ws_{ts}"
    password = "Password123!"
    
    # Onboard
    req = urllib.request.Request(
        f"{BASE_URL}/api/v1/auth/register",
        data=json.dumps({"device_id": device_id, "password": password}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    with urllib.request.urlopen(req) as resp:
        user_data = json.loads(resp.read().decode("utf-8"))
    
    # Login
    req = urllib.request.Request(
        f"{BASE_URL}/api/v1/auth/login",
        data=json.dumps({"device_id": device_id, "password": password}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    with urllib.request.urlopen(req) as resp:
        login_data = json.loads(resp.read().decode("utf-8"))
        
    return user_data, login_data["access_token"]

if __name__ == "__main__":
    import time
    user_data, token = get_auth_token()
    print("Obtained auth user:", user_data["id"])
    print("Token prefix:", token[:20] + "...")
