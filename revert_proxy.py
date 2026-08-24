import os
import re

file_path = r'e:\vc code\.vscode\trash tracker\garbage_ai model v2\flask_app.py'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Pattern to remove proxy block
pattern = r'# ---------------------------------------------------------.*?@app\.route\(''/api/snapshots'', methods=\[''GET''\]\)'
content = re.sub(pattern, "@app.route('/api/snapshots', methods=['GET'])", content, flags=re.DOTALL)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Proxy removed")
