import requests

try:
    resp = requests.get('http://127.0.0.1:5002/api/snapshots')
    print("Direct 5002 call:", resp.status_code)
except Exception as e:
    print("Direct 5002 call failed:", e)

