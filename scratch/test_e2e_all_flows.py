import json
import time
import urllib.request
import urllib.parse
import urllib.error

BASE_URL = "http://localhost:28080"

def req(method, path, token=None, data=None):
    url = f"{BASE_URL}{path}"
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    
    encoded = json.dumps(data).encode("utf-8") if data else None
    request = urllib.request.Request(url, data=encoded, headers=headers, method=method)
    
    try:
        with urllib.request.urlopen(request) as resp:
            body = resp.read().decode("utf-8")
            return resp.status, json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8")
        try:
            parsed = json.loads(body)
        except Exception:
            parsed = {"error": body}
        return e.code, parsed

def run():
    print("=== 1. AUTHENTICATION & USER CREATION ===")
    ts = int(time.time())
    
    # User A
    dev_a = f"dev_user_a_{ts}"
    st, res_a = req("POST", "/api/v1/auth/register", data={"device_id": dev_a, "password": "Password123!"})
    user_a_id = res_a['id']
    print(f"User A Register: status={st}, id={user_a_id}")
    
    st, login_a = req("POST", "/api/v1/auth/login", data={"device_id": dev_a, "password": "Password123!"})
    token_a = login_a["access_token"]
    print(f"User A Login: status={st}, token_len={len(token_a)}")
    
    # User B
    dev_b = f"dev_user_b_{ts}"
    st, res_b = req("POST", "/api/v1/auth/register", data={"device_id": dev_b, "password": "Password123!"})
    user_b_id = res_b['id']
    print(f"User B Register: status={st}, id={user_b_id}")
    
    st, login_b = req("POST", "/api/v1/auth/login", data={"device_id": dev_b, "password": "Password123!"})
    token_b = login_b["access_token"]
    print(f"User B Login: status={st}, token_len={len(token_b)}")
    
    print("\n=== 2. USER PROFILE & PREFERENCES ===")
    st, profile = req("GET", "/api/v1/user/profile", token=token_a)
    print(f"User A Profile: status={st}, pseudonym={profile.get('pseudonym')}")
    
    st, updated = req("PUT", "/api/v1/user/profile", token=token_a, data={"display_name": "Alice", "bio": "EasyChat User"})
    print(f"Update Profile: status={st}")
    
    print("\n=== 3. CHAT ROOM CREATION & MESSAGING ===")
    # Correct camelCase JSON payload keys: userA, userB
    st, room = req("POST", "/api/v1/chat/rooms", token=token_a, data={"userA": user_a_id, "userB": user_b_id})
    print(f"Create Room User A <-> User B: status={st}, room={room}")

if __name__ == "__main__":
    run()
