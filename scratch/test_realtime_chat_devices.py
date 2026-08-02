import asyncio
import json
import time
import urllib.request
import uuid
import websockets

BASE_HTTP_URL = "http://localhost:28080"
BASE_WS_URL = "ws://localhost:28080/ws"

def onboard_user(device_id):
    req = urllib.request.Request(
        f"{BASE_HTTP_URL}/api/v1/auth/register",
        data=json.dumps({"device_id": device_id, "password": "Password123!"}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    with urllib.request.urlopen(req) as resp:
        user_data = json.loads(resp.read().decode("utf-8"))
    
    req = urllib.request.Request(
        f"{BASE_HTTP_URL}/api/v1/auth/login",
        data=json.dumps({"device_id": device_id, "password": "Password123!"}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    with urllib.request.urlopen(req) as resp:
        login_data = json.loads(resp.read().decode("utf-8"))
        
    return user_data, login_data["access_token"]

def create_room(token_a, user_a_id, user_b_id):
    req = urllib.request.Request(
        f"{BASE_HTTP_URL}/api/v1/chat/rooms",
        data=json.dumps({"userA": user_a_id, "userB": user_b_id}).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {token_a}"},
        method="POST"
    )
    with urllib.request.urlopen(req) as resp:
        room_data = json.loads(resp.read().decode("utf-8"))
    return room_data["roomId"]

async def run_realtime_test():
    print("--- 1. REGISTERING USER A (DEVICE A) & USER B (DEVICE B) ---")
    ts = int(time.time())
    user_a, token_a = onboard_user(f"dev_phone_a_{ts}")
    user_b, token_b = onboard_user(f"dev_phone_b_{ts}")
    print(f"Device A User: {user_a['id']}")
    print(f"Device B User: {user_b['id']}")

    print("\n--- 2. CREATING MUTUAL CHAT ROOM ---")
    room_id = create_room(token_a, user_a['id'], user_b['id'])
    print(f"Resolved Room ID: {room_id}")

    print("\n--- 3. CONNECTING WEBSOCKET CLIENTS FOR PHONE A & PHONE B ---")
    ws_url_a = f"{BASE_WS_URL}?token={token_a}"
    ws_url_b = f"{BASE_WS_URL}?token={token_b}"

    async with websockets.connect(ws_url_a) as ws_a, websockets.connect(ws_url_b) as ws_b:
        print("Phone A WebSocket Connected OK!")
        print("Phone B WebSocket Connected OK!")

        # Subscribe Phone B to room typing/events
        sub_packet = json.dumps({"type": "SUBSCRIBE_ROOM", "room_id": room_id})
        await ws_b.send(sub_packet)

        # Valid UUIDv4 message_id and idempotency_key
        msg_id = str(uuid.uuid4())
        idemp_key = str(uuid.uuid4())
        msg_text = "Hello from Phone A to Phone B!"

        msg_packet = json.dumps({
            "type": "MESSAGE",
            "message": {
                "message_id": msg_id,
                "room_id": room_id,
                "sender_id": user_a['id'],
                "encrypted_payload": "SGVsbG8gZnJvbSBQaG9uZSBBIHRvIFBob25lIEIh",
                "idempotency_key": idemp_key,
                "created_at": "2026-07-24T05:54:00Z"
            }
        })

        print(f"\nPhone A sending message: '{msg_text}' (Message UUID: {msg_id})...")
        start_time = time.time()
        await ws_a.send(msg_packet)

        # Phone B listens for incoming message over WebSocket
        print("Phone B listening for real-time WebSocket event...")
        recv_data = await asyncio.wait_for(ws_b.recv(), timeout=15.0)
        end_time = time.time()

        latency_ms = (end_time - start_time) * 1000
        parsed = json.loads(recv_data)
        print(f"\nSUCCESS! Phone B received real-time WebSocket event in {latency_ms:.2f} ms:")
        print(json.dumps(parsed, indent=2))

if __name__ == "__main__":
    asyncio.run(run_realtime_test())
