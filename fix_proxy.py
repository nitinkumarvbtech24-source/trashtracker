import os
import re

file_path = r'e:\vc code\.vscode\trash tracker\garbage_ai model v2\flask_app.py'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

proxy_code = '''
# ---------------------------------------------------------
# PROXY TO HEALTH AI ON PORT 5002
# This allows a single Ngrok tunnel (port 5001) to serve both AIs!
# ---------------------------------------------------------
@app.route('/health_api/snapshots', methods=['GET', 'OPTIONS'])
def proxy_health_snapshots():
    if request.method == 'OPTIONS':
        return jsonify({"message": "ok"}), 200
    try:
        resp = requests.get('http://127.0.0.1:5002/api/snapshots')
        return Response(resp.content, resp.status_code, resp.raw.headers.items())
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/health_api/process_frame', methods=['POST', 'OPTIONS'])
def proxy_health_process_frame():
    if request.method == 'OPTIONS':
        return jsonify({"message": "ok"}), 200
    try:
        resp = requests.post('http://127.0.0.1:5002/process_frame', json=request.json)
        return Response(resp.content, resp.status_code, resp.raw.headers.items())
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/snapshots', methods=['GET'])
'''

content = content.replace("@app.route('/api/snapshots', methods=['GET'])", proxy_code, 1)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Proxy code injected into flask_app.py")
