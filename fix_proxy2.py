import os

file_path = r'e:\vc code\.vscode\trash tracker\garbage_ai model v2\flask_app.py'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

bad_proxy = '''        resp = requests.get('http://127.0.0.1:5002/api/snapshots')
        return Response(resp.content, resp.status_code, resp.raw.headers.items())'''

good_proxy = '''        resp = requests.get('http://127.0.0.1:5002/api/snapshots')
        return jsonify(resp.json()), resp.status_code'''

content = content.replace(bad_proxy, good_proxy)

bad_proxy2 = '''        resp = requests.post('http://127.0.0.1:5002/process_frame', json=request.json)
        return Response(resp.content, resp.status_code, resp.raw.headers.items())'''

good_proxy2 = '''        resp = requests.post('http://127.0.0.1:5002/process_frame', json=request.json)
        return jsonify(resp.json()), resp.status_code'''

content = content.replace(bad_proxy2, good_proxy2)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Proxy headers fixed")
