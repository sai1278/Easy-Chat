import requests

url = "http://192.168.31.60:8090/api/v1/auth/register"
payload = {
    "device_id": "dev_test_device_a",
    "password": "password123"
}
headers = {
    "Content-Type": "application/json"
}

print(f"POSTing to {url}...")
resp = requests.post(url, json=payload, headers=headers)
print("REGISTER Status:", resp.status_code)
print("REGISTER Body:", resp.text)

login_url = "http://192.168.31.60:8090/api/v1/auth/login"
print(f"POSTing to {login_url}...")
resp_login = requests.post(login_url, json=payload, headers=headers)
print("LOGIN Status:", resp_login.status_code)
print("LOGIN Body:", resp_login.text)
