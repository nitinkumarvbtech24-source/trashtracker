import requests

try:
    resp = requests.get('http://127.0.0.1:5001/health_api/api/snapshots')
    print("Proxy snapshots call:", resp.status_code)
    print("Content:", resp.text[:100])
except Exception as e:
    print("Proxy snapshots call failed:", e)

