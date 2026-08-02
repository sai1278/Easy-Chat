import urllib.request
import urllib.error

url = "http://127.0.0.1:18080/api/v1/user/profile"
req = urllib.request.Request(url)

try:
    with urllib.request.urlopen(req) as resp:
        print("Status:", resp.getcode())
except urllib.error.HTTPError as e:
    print("Status:", e.code)
    print("Body:", e.read().decode())
except Exception as e:
    print("Error:", e)
