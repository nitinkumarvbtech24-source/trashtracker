import os

file_path = r'e:\vc code\.vscode\trash tracker\garbage_ai model v2\flask_app.py'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace("@app.route('/health_api/snapshots'", "@app.route('/health_api/api/snapshots'")

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Route updated")
